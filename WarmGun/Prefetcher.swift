import Foundation
import WarmGunKit

/// Keeps the clips around the playhead on disk before they are needed.
///
/// Given a plan (nearest clips first, see `PrefetchPlanner`), it downloads
/// what is missing a few at a time, drops downloads that fell out of the plan,
/// and evicts the least recently used cached clips that the plan does not
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
    private let cache: ClipCache
    private var links = LinkCache()
    private var clips: [String: Clip] = [:]
    private var plan: [String] = []
    private var planGeneration = 0
    private var inFlight: [String: Flight] = [:]
    private var failures: [String: (attempts: Int, last: Date)] = [:]
    private var capBytes: Int64
    private let parallelism = 3
    private let failureCooldown: TimeInterval = 8
    private let continuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    init(client: PCloudClient, cache: ClipCache, capBytes: Int64) {
        self.client = client
        self.cache = cache
        self.capBytes = capBytes
        var continuation: AsyncStream<Event>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func setCap(bytes: Int64) {
        capBytes = bytes
    }

    /// Adopt a new window. Stale generations are dropped rather than applied —
    /// two `sync()`s in quick succession may land here out of order, and the
    /// older plan must not win.
    func replan(_ order: [String], clips: [String: Clip], generation: Int) async {
        guard generation >= planGeneration else { return }
        planGeneration = generation
        self.clips.merge(clips) { _, new in new }
        plan = order
        let wanted = Set(order)
        for (path, flight) in inFlight where !wanted.contains(path) {
            flight.task.cancel()
            inFlight[path] = nil
        }
        await pump()
    }

    /// A short-lived direct URL for a clip that streams instead of caching —
    /// the same link cache and expiry rules the downloads use.
    func streamURL(for clip: Clip) async throws -> URL {
        try await link(for: clip)
    }

    private func pump() async {
        guard inFlight.count < parallelism else { return }
        let cached = await cache.cachedPaths()
        let now = Date()
        var cooling = false
        for path in plan where inFlight.count < parallelism {
            guard !cached.contains(path), inFlight[path] == nil, let clip = clips[path] else { continue }
            // A path that just failed sits out a beat instead of hammering the
            // same broken link in a tight loop; the delayed pump below retries.
            if let failure = failures[path], now.timeIntervalSince(failure.last) < failureCooldown {
                cooling = true
                continue
            }
            let token = UUID()
            let task = Task { [weak self] in _ = await self?.fetch(clip, token: token) }
            inFlight[path] = Flight(task: task, token: token)
        }
        if cooling && inFlight.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.failureCooldown ?? 8))
                await self?.pump()
            }
        }
    }

    private func fetch(_ clip: Clip, token: UUID) async {
        defer {
            // Only this flight's own registration — replan may have cancelled
            // it and pump may already have a replacement in the slot.
            if inFlight[clip.path]?.token == token { inFlight[clip.path] = nil }
        }
        do {
            try await fetchOnce(clip, retryOnStaleLink: true)
            failures[clip.path] = nil
            continuation.yield(.ready(clip.path))
            await evict()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            // URLSession's spelling of the same thing — a window shift, not a
            // failure, and never something to alarm anyone with.
            return
        } catch {
            let attempts = (failures[clip.path]?.attempts ?? 0) + 1
            failures[clip.path] = (attempts, Date())
            let loginRequired = (error as? PCloudError)?.isLoginRequired ?? false
            continuation.yield(.failed(clip.path, error.localizedDescription,
                                       attempts: attempts, loginRequired: loginRequired))
        }
        await pump()
    }

    enum FetchFailure: Error, LocalizedError {
        case wrongSize(got: Int64, expected: Int64)
        var errorDescription: String? {
            switch self {
            case .wrongSize(let got, let expected):
                return "Downloaded \(got) bytes where the index says \(expected) — not the clip (a captive portal?)"
            }
        }
    }

    /// A link that pCloud has let expire answers with a 4xx; that means
    /// "re-link and try again", never "the clip is gone".
    private func fetchOnce(_ clip: Clip, retryOnStaleLink: Bool) async throws {
        let url = try await link(for: clip)
        do {
            let tmp = try await client.download(url)
            try Task.checkCancellation()
            // The index knows the clip's exact size; a 200 whose body is any
            // other length is not the clip — travel wifi answers with captive
            // portals and proxy pages, and those must never reach the player.
            let got = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? -1
            guard got == clip.size else {
                try? FileManager.default.removeItem(at: tmp)
                throw FetchFailure.wrongSize(got: got, expected: clip.size)
            }
            try await cache.store(temporary: tmp, for: clip.path)
        } catch PCloudClient.Failure.http(let code) where retryOnStaleLink && (400..<500).contains(code) {
            links.forget(clip.fileID)
            try await fetchOnce(clip, retryOnStaleLink: false)
        }
    }

    private func link(for clip: Clip) async throws -> URL {
        if let url = links.url(for: clip.fileID, now: Date()) { return url }
        let response = try await client.fileLink(fileID: clip.fileID)
        guard let url = response.url else { throw PCloudClient.Failure.noLink }
        links.store(url: url, for: clip.fileID, expires: response.expires)
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
