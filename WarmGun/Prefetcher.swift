import Foundation
import WarmGunKit

actor Prefetcher {
    enum Event: Sendable {
        case ready(String)
        case failed(String, String, attempts: Int, loginRequired: Bool)
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
            // URLSession's spelling of cancellation.
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

    /// An expired pCloud link answers 4xx.
    private func fetchOnce(_ video: Video, retryOnStaleLink: Bool) async throws {
        let url = try await link(for: video)
        do {
            let tmp = try await client.download(url)
            try Task.checkCancellation()
            // A 200 of any other length is a captive portal or a proxy page off travel wifi.
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
