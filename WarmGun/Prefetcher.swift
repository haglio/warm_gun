import Foundation
import WarmGunKit

/// Keeps the videos around the playhead on disk before they are needed.
///
/// Given a plan (nearest videos first, see `PrefetchPlanner`), it downloads
/// what is missing a few at a time, drops downloads that fell out of the plan,
/// and evicts the least recently used cached videos that the plan does not
/// protect once the cache is over its cap. The scenes too big to cache whole
/// are not planned at all — they stream, and this hands out their links.
actor Prefetcher {
    enum Event: Sendable {
        /// `path` is on disk and playable-sized.
        case ready(String)
        /// One attempt on `path` failed; `attempts` is the consecutive count,
        /// and `loginRequired` says the token itself was refused.
        case failed(String, String, attempts: Int, loginRequired: Bool)
        /// The cap was enforced; these paths left the disk.
        case evicted([String])
    }

    private struct Flight {
        let task: Task<Void, Never>
        let token: UUID
    }

    private let client: PCloudClient
    private let cache: VideoCache
    private var links = LinkCache()
    private var videos: [String: Video] = [:]
    private var plan: [String] = []
    private var planGeneration = 0
    private var inFlight: [String: Flight] = [:]
    private var failures: [String: (attempts: Int, last: Date)] = [:]
    private let capBytes: Int64
    private let parallelism = 3
    private let failureCooldown: TimeInterval = 8
    private let continuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    init(client: PCloudClient, cache: VideoCache, capBytes: Int64) {
        self.client = client
        self.cache = cache
        self.capBytes = capBytes
        var continuation: AsyncStream<Event>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// Adopt a new window. Stale generations are dropped rather than applied —
    /// two `sync()`s in quick succession may land here out of order, and the
    /// older plan must not win.
    func replan(_ order: [String], videos: [String: Video], generation: Int) async {
        guard generation >= planGeneration else { return }
        planGeneration = generation
        self.videos.merge(videos) { _, new in new }
        plan = order
        let wanted = Set(order)
        for (path, flight) in inFlight where !wanted.contains(path) {
            flight.task.cancel()
            inFlight[path] = nil
        }
        await pump()
    }

    /// A short-lived direct URL for a video that streams instead of caching —
    /// the same link cache and expiry rules the downloads use.
    func streamURL(for video: Video) async throws -> URL {
        try await link(for: video)
    }

    private func pump() async {
        guard inFlight.count < parallelism else { return }
        let cached = await cache.cachedPaths()
        let now = Date()
        var cooling = false
        for path in plan where inFlight.count < parallelism {
            guard !cached.contains(path), inFlight[path] == nil, let video = videos[path] else { continue }
            // A path that just failed sits out a beat instead of hammering the
            // same broken link in a tight loop; the delayed pump below retries.
            if let failure = failures[path], now.timeIntervalSince(failure.last) < failureCooldown {
                cooling = true
                continue
            }
            let token = UUID()
            let task = Task { [weak self] in _ = await self?.fetch(video, token: token) }
            inFlight[path] = Flight(task: task, token: token)
        }
        if cooling && inFlight.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.failureCooldown ?? 8))
                await self?.pump()
            }
        }
    }

    private func fetch(_ video: Video, token: UUID) async {
        defer {
            // Only this flight's own registration — replan may have canceled
            // it and pump may already have a replacement in the slot.
            if inFlight[video.path]?.token == token { inFlight[video.path] = nil }
        }
        do {
            try await fetchOnce(video, retryOnStaleLink: true)
            failures[video.path] = nil
            continuation.yield(.ready(video.path))
            await evict()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            // URLSession's spelling of the same thing — a window shift, not a
            // failure, and never something to alarm anyone with.
            return
        } catch {
            let attempts = (failures[video.path]?.attempts ?? 0) + 1
            failures[video.path] = (attempts, Date())
            let loginRequired = (error as? PCloudError)?.isLoginRequired ?? false
            continuation.yield(.failed(video.path, error.localizedDescription,
                                       attempts: attempts, loginRequired: loginRequired))
        }
        await pump()
    }

    enum FetchFailure: Error, LocalizedError {
        case wrongSize(got: Int64, expected: Int64)
        var errorDescription: String? {
            switch self {
            case .wrongSize(let got, let expected):
                return "Downloaded \(got) bytes where the index says \(expected) — not the video (a captive portal?)"
            }
        }
    }

    /// A link that pCloud has let expire answers with a 4xx; that means
    /// "re-link and try again", never "the video is gone".
    private func fetchOnce(_ video: Video, retryOnStaleLink: Bool) async throws {
        let url = try await link(for: video)
        do {
            let tmp = try await client.download(url)
            try Task.checkCancellation()
            // The index knows the video's exact size; a 200 whose body is any
            // other length is not the video — travel wifi answers with captive
            // portals and proxy pages, and those must never reach the player.
            let got = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? -1
            guard got == video.size else {
                try? FileManager.default.removeItem(at: tmp)
                throw FetchFailure.wrongSize(got: got, expected: video.size)
            }
            try await cache.store(temporary: tmp, for: video.path)
        } catch PCloudClient.Failure.http(let code) where retryOnStaleLink && (400..<500).contains(code) {
            links.forget(video.fileID)
            try await fetchOnce(video, retryOnStaleLink: false)
        }
    }

    private func link(for video: Video) async throws -> URL {
        if let url = links.url(for: video.fileID, now: Date()) { return url }
        let response = try await client.fileLink(fileID: video.fileID)
        guard let url = response.url else { throw PCloudClient.Failure.noLink }
        links.store(url: url, for: video.fileID, expires: response.expires)
        return url
    }

    private func evict() async {
        let cached = await cache.cachedFiles()
        let doomed = PrefetchPlanner.evictions(cached: cached, keep: Set(plan), capBytes: capBytes)
        if !doomed.isEmpty {
            await cache.remove(doomed)
            continuation.yield(.evicted(doomed))
        }
    }
}
