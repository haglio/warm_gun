import Foundation

/// What to fetch next, and what to throw away to make room for it.
///
/// The playlist is deterministic, so both the future and the past of a run are
/// knowable: the window keeps clips resident on either side of the one playing
/// and never waits on the network for a tap.
public enum PrefetchPlanner {
    /// The order to fetch the window in — nearest first, the clip on screen
    /// ahead of everything.
    ///
    /// The playlist is a ring, so the offsets wrap; on a run shorter than the
    /// window that would name the same clip several times, and the cache is
    /// keyed by file, so each one is asked for once and the plan is never longer
    /// than the run itself.
    public static func plan(playlist: [String], index: Int, ahead: Int, behind: Int) -> [String] {
        guard !playlist.isEmpty else { return [] }
        // The cap is on the work, not just the answer: a window wider than the
        // run itself names nothing the run does not already hold.
        let ahead = min(ahead, playlist.count)
        let behind = min(behind, playlist.count)
        var planned: [String] = []
        var seen: Set<String> = []
        for offset in offsets(ahead: ahead, behind: behind) {
            let path = playlist[wrap(index + offset, playlist.count)]
            if seen.insert(path).inserted { planned.append(path) }
            if planned.count == playlist.count { break }
        }
        return planned
    }

    /// A clip already on disk: what it costs to keep, and when it last earned
    /// its place.
    public struct CachedFile: Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let lastUsed: Date

        public init(path: String, size: Int64, lastUsed: Date) {
            self.path = path
            self.size = size
            self.lastUsed = lastUsed
        }
    }

    /// What to delete to bring the cache back under its cap: least recently
    /// played first, and only as far as it takes.
    ///
    /// Nothing in `keep` — the live window — is ever offered up, even when that
    /// leaves the cache over the cap: those clips are what the next taps play, so
    /// deleting one only buys the same download back again.
    public static func evictions(cached: [CachedFile], keep: Set<String>, capBytes: Int64) -> [String] {
        var total = cached.reduce(Int64(0)) { $0 + $1.size }
        var evicted: [String] = []
        let candidates = cached.filter { !keep.contains($0.path) }
            .sorted { ($0.lastUsed, $0.path) < ($1.lastUsed, $1.path) }
        for candidate in candidates {
            guard total > capBytes else { break }
            evicted.append(candidate.path)
            total -= candidate.size
        }
        return evicted
    }

    /// Offsets from the current entry, in the order they are worth fetching:
    /// two forward for every one backward, so the window leans into the future —
    /// next is the gesture of the run — without ever abandoning the past. When
    /// one side runs out the other simply carries on.
    private static func offsets(ahead: Int, behind: Int) -> [Int] {
        var offsets = [0]
        var forward = 1
        var backward = 1
        while forward <= ahead || backward <= behind {
            for _ in 0..<2 where forward <= ahead {
                offsets.append(forward)
                forward += 1
            }
            if backward <= behind {
                offsets.append(-backward)
                backward += 1
            }
        }
        return offsets
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        let remainder = value % count
        return remainder < 0 ? remainder + count : remainder
    }
}
