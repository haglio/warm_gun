import Foundation

public enum PrefetchPlanner {
    public static func plan(playlist: [String], index: Int, ahead: Int, back: Int) -> [String] {
        guard !playlist.isEmpty else { return [] }
        let ahead = min(ahead, playlist.count)
        let back = min(back, playlist.count)
        var planned: [String] = []
        var seen: Set<String> = []
        for offset in offsets(ahead: ahead, back: back) {
            let path = playlist[(index + offset).wrapped(into: playlist.count)]
            if seen.insert(path).inserted { planned.append(path) }
            if planned.count == playlist.count { break }
        }
        return planned
    }

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

    private static func offsets(ahead: Int, back: Int) -> [Int] {
        var offsets = [0]
        var forward = 1
        var backward = 1
        while forward <= ahead || backward <= back {
            for _ in 0..<2 where forward <= ahead {
                offsets.append(forward)
                forward += 1
            }
            if backward <= back {
                offsets.append(-backward)
                backward += 1
            }
        }
        return offsets
    }
}
