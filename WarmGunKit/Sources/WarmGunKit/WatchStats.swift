import Foundation

/// The three things playback can say about a clip, and the only vocabulary the
/// journal and the desktop's `watch_stats.json` share.
public enum WatchEvent: String, Codable, Sendable {
    case completion
    case skip
    case lock
}

/// What one clip has earned: watched through, skipped early, or locked.
public struct WatchEntry: Codable, Equatable, Sendable {
    public var completions: Int
    public var skips: Int
    public var locks: Int

    public init(completions: Int = 0, skips: Int = 0, locks: Int = 0) {
        self.completions = completions
        self.skips = skips
        self.locks = locks
    }

    /// A count absent from a persisted row is zero, as the desktop reads its
    /// own file (`entry.get(field, 0)`) — never a decoding failure.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completions = try c.decodeIfPresent(Int.self, forKey: .completions) ?? 0
        skips = try c.decodeIfPresent(Int.self, forKey: .skips) ?? 0
        locks = try c.decodeIfPresent(Int.self, forKey: .locks) ?? 0
    }
}

/// How often each clip has been watched through, skipped, or locked — the
/// counts that bias the shuffle so loved clips come round more and chronically
/// skipped ones fade. Keyed by library-relative original path.
public struct WatchStats: Codable, Equatable, Sendable {
    public var entries: [String: WatchEntry]

    public init(entries: [String: WatchEntry] = [:]) {
        self.entries = entries
    }

    public mutating func record(_ event: WatchEvent, path: String) {
        var entry = entries[path] ?? WatchEntry()
        switch event {
        case .completion: entry.completions += 1
        case .skip: entry.skips += 1
        case .lock: entry.locks += 1
        }
        entries[path] = entry
    }

    /// The relative playback weight of one clip; a clip with no history weighs
    /// 1.0, the neutral weight every fresh clip has.
    public func weight(for path: String) -> Double {
        entries[path].map(Self.weight(of:)) ?? 1.0
    }

    /// The desktop's curve (`watch_stats.py:weight_for`): a score of
    /// completions + 3·locks − skips, softened by three and clamped to ±3
    /// doublings, so no clip is ever more than eight times as frequent — or as
    /// rare — as a fresh one.
    public static func weight(of entry: WatchEntry) -> Double {
        let score = Double(entry.completions) + lockScore * Double(entry.locks) - Double(entry.skips)
        let doublings = max(-maxDoublings, min(maxDoublings, score / scoreSoftening))
        return pow(2.0, doublings)
    }

    private static let lockScore = 3.0
    private static let scoreSoftening = 3.0
    private static let maxDoublings = 3.0
}

/// The two random primitives the shuffle is built from, kept apart from the
/// counts so they can be reasoned about — and seeded — on their own.
public enum Weighting {
    /// Whether a clip of this weight makes the build at all. Neutral-or-loved
    /// clips always play; a disliked one sits out in proportion to its weight,
    /// which is the continuous form of the weird gesture's hard removal.
    public static func passesInclusion(weight: Double, rng: inout some RandomNumberGenerator) -> Bool {
        weight >= 1.0 || uniform(&rng) < weight
    }

    /// Shuffle with bias: heavier items tend to land earlier.
    ///
    /// Efraimidis–Spirakis sampling — each item draws a key `-log(u)/w` and the
    /// list sorts ascending, which is a weighted draw without replacement. With
    /// all weights equal it degenerates to a uniform shuffle. Every key is drawn
    /// in the order the items arrive, before any comparison happens, so one seed
    /// always yields one order.
    public static func weightedShuffle<T>(_ items: [T], weight: (T) -> Double,
                                          rng: inout some RandomNumberGenerator) -> [T] {
        var keyed: [(item: T, key: Double)] = []
        keyed.reserveCapacity(items.count)
        for item in items {
            // A weight that is not a positive number draws as neutral, the way
            // the desktop coerces a dead weight to 1.0 — a negative key would
            // front-load the item, the exact inverse of the intent.
            let w = weight(item)
            let safe = w.isFinite && w > 0 ? w : 1.0
            keyed.append((item, -log(max(uniform(&rng), 1e-12)) / safe))
        }
        return keyed.sorted { $0.key < $1.key }.map(\.item)
    }

    /// A uniform draw in `[0, 1)` — Python's `random.random()`, which both
    /// primitives below are written against.
    private static func uniform(_ rng: inout some RandomNumberGenerator) -> Double {
        Double(rng.next() >> 11) * 0x1p-53
    }
}

/// Turns a run of playback samples into watch events.
///
/// Player-agnostic, exactly as the desktop's is: fed periodic (path, fraction)
/// samples plus notice of user navigation and of discards, it says which clips
/// were watched through and which were skipped. A held clip counts again on
/// every repeat-one wrap. Anything else — the automatic advance on unlock, a
/// clip that vanished — is deliberately neutral, because only what the viewer
/// did should move a clip's weight.
public struct WatchTracker: Sendable {
    /// At or past this fraction the clip counts as watched.
    public static let completeFraction = 0.85
    /// At or below this fraction, leaving counts against the clip.
    public static let skipFraction = 0.60
    /// How recently a tap must have happened for a departure to be the viewer's doing.
    public static let navWindow: TimeInterval = 3.0
    /// How far back a position has to jump before it is a wrap and not jitter.
    private static let wrapDrop = 0.5

    private var path = ""
    private var maxFraction = 0.0
    private var lastNavAt = Date.distantPast
    private var suppressDeparted = false

    public init() {}

    public mutating func noteUserNav(now: Date) {
        lastNavAt = now
    }

    public mutating func noteDiscard() {
        suppressDeparted = true
    }

    /// One position report. Two things can happen: the clip on screen looped,
    /// or a different clip took its place — the tracker never sees an "ended".
    public mutating func sample(path: String, fraction: Double, now: Date) -> [(event: WatchEvent, path: String)] {
        if path == self.path { return wrapped(to: fraction) }
        let departure = departureEvent(now: now)
        self.path = path
        maxFraction = max(0.0, fraction)
        suppressDeparted = false
        return departure.map { [$0] } ?? []
    }

    /// The clip is still on screen, so the only news a sample can carry is a
    /// jump back to the top: a satellite has no seek control, so a big backward
    /// move from near the end can only be a repeat-one wrap, and a held clip
    /// books one full watch for each of them.
    private mutating func wrapped(to fraction: Double) -> [(event: WatchEvent, path: String)] {
        guard !path.isEmpty, maxFraction >= Self.completeFraction,
              fraction < maxFraction - Self.wrapDrop else {
            maxFraction = max(maxFraction, fraction)
            return []
        }
        maxFraction = max(0.0, fraction)
        return [(.completion, path)]
    }

    /// What the clip leaving the screen earned. Reaching the end is a watch
    /// however the roll-on happened; leaving it barely started counts against it
    /// only when a tap just before says the viewer chose to leave. A discard —
    /// the clip marked weird and pulled out of the playlist — is a harder
    /// judgement already made, so it swallows the departure entirely.
    private func departureEvent(now: Date) -> (event: WatchEvent, path: String)? {
        guard !path.isEmpty, !suppressDeparted else { return nil }
        if maxFraction >= Self.completeFraction { return (.completion, path) }
        let navRecent = now.timeIntervalSince(lastNavAt) <= Self.navWindow
        guard navRecent, maxFraction <= Self.skipFraction else { return nil }
        return (.skip, path)
    }
}
