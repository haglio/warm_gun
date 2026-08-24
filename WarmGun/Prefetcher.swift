import Foundation
import WarmGunKit

/// Keeps the clips around the playhead on disk before they are needed.
///
/// Given a plan (nearest clips first, see `PrefetchPlanner`), it downloads
/// what is missing a few at a time, drops downloads that fell out of the plan,
/// and evicts the least recently used cached clips that the plan does not
/// protect once the cache is over its cap. A separate backlog behind the plan
/// serves "download everything": it only ever draws from spare download slots,
/// so the window around the playhead always wins.
actor Prefetcher {
    enum Event: Sendable {
        case ready(String)
        case failed(String, String)
        case backlog(remaining: Int, total: Int)
    }

    private let client: PCloudClient
    private let cache: ClipCache
    private var links = LinkCache()
    private var clips: [String: Clip] = [:]
    private var plan: [String] = []
    private var backlog: [String] = []
    private var backlogTotal = 0
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var capBytes: Int64
    private let parallelism = 3
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

    func replan(_ order: [String], clips: [String: Clip]) async {
        self.clips.merge(clips) { _, new in new }
        plan = order
        let wanted = Set(order).union(backlog)
        for (path, task) in inFlight where !wanted.contains(path) {
            task.cancel()
            inFlight[path] = nil
        }
        await pump()
    }

    /// Queue every clip not yet cached, behind the window. Re-issuing replaces
    /// the backlog rather than doubling it.
    func downloadAll(_ paths: [String], clips: [String: Clip]) async {
        self.clips.merge(clips) { _, new in new }
        let cached = await cache.cachedPaths()
        backlog = paths.filter { !cached.contains($0) }
        backlogTotal = backlog.count
        continuation.yield(.backlog(remaining: backlog.count, total: backlogTotal))
        await pump()
    }

    func cancelBacklog() {
        backlog = []
        backlogTotal = 0
        continuation.yield(.backlog(remaining: 0, total: 0))
    }

    private func pump() async {
        guard inFlight.count < parallelism else { return }
        let cached = await cache.cachedPaths()
        let candidates = plan + backlog
        for path in candidates where inFlight.count < parallelism {
            guard !cached.contains(path), inFlight[path] == nil, let clip = clips[path] else { continue }
            inFlight[path] = Task { [weak self] in
                await self?.fetch(clip)
            }
        }
    }

    private func fetch(_ clip: Clip) async {
        defer { inFlight[clip.path] = nil }
        do {
            try await fetchOnce(clip, retryOnStaleLink: true)
            continuation.yield(.ready(clip.path))
            await evict()
        } catch is CancellationError {
            return
        } catch {
            continuation.yield(.failed(clip.path, error.localizedDescription))
        }
        backlog.removeAll { $0 == clip.path }
        if backlogTotal > 0 {
            continuation.yield(.backlog(remaining: backlog.count, total: backlogTotal))
            if backlog.isEmpty { backlogTotal = 0 }
        }
        await pump()
    }

    /// A link that pCloud has let expire answers with a 4xx; that means
    /// "re-link and try again", never "the clip is gone".
    private func fetchOnce(_ clip: Clip, retryOnStaleLink: Bool) async throws {
        let url = try await link(for: clip)
        do {
            let tmp = try await client.download(url)
            try Task.checkCancellation()
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
        let keep = Set(plan).union(backlog.isEmpty ? [] : Set(cached.map(\.path)))
        let doomed = PrefetchPlanner.evictions(cached: cached, keep: keep, capBytes: capBytes)
        if !doomed.isEmpty { await cache.remove(doomed) }
    }
}
