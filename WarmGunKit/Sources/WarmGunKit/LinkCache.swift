import Foundation

/// The download URLs pCloud has handed out, kept so the prefetcher does not
/// spend a `getfilelink` round-trip per clip on a phone connection. Every link
/// dies at a stated moment, so the cache is only useful if it is asked with a
/// clock in hand — which is why `now` is a parameter and never read from here.
public struct LinkCache: Equatable, Sendable {
    private struct Link: Equatable {
        let url: URL
        let expires: Date
    }

    private var links: [Int64: Link] = [:]

    public init() {}

    /// Keyed by file id rather than by path, because the weird gesture renames
    /// clips out from under any path a link was fetched for.
    public mutating func store(url: URL, for fileID: Int64, expires: Date) {
        links[fileID] = Link(url: url, expires: expires)
    }

    /// Throw one link away. A fetch that failed on a link the cache still
    /// believed in means the URL died early, not that the clip is gone: the
    /// answer is to re-link and retry, and this is how the dead one leaves.
    public mutating func forget(_ fileID: Int64) {
        links[fileID] = nil
    }

    /// Drop everything that has already expired. `url(for:now:)` would refuse
    /// these anyway; this is what stops a session that runs for hours from
    /// carrying a dead link for every clip it has ever played.
    public mutating func purge(now: Date) {
        links = links.filter { $0.value.expires > now }
    }

    /// The link, or nil when there isn't one or it is too close to the end of
    /// its life to hand to a download. The default margin is a minute: a clip
    /// is a couple of megabytes and a link that expires mid-transfer fails the
    /// fetch, which costs far more than re-linking would have.
    public func url(for fileID: Int64, now: Date, margin: TimeInterval = 60) -> URL? {
        guard let link = links[fileID], link.expires > now.addingTimeInterval(margin) else { return nil }
        return link.url
    }
}
