import Foundation

/// How much each clip is owed in the draw, as the desktop stamped it.
///
/// Evolver sums what Fun Time and Warm Gun each completed, skipped and locked,
/// and writes the resulting weight onto every library video's metadata sidecar
/// (`evolver/util/watch.py`). Both apps read that one number instead of each
/// keeping a copy of the formula — so what the phone did on the road and what
/// the desktop did at home move the same clip, and neither side can drift.
///
/// A clip with no stamp weighs 1.0: a fresh clip, a clip whose sidecar has not
/// reached the phone yet, and a clip the stage has not visited are all simply
/// without evidence, which is what neutral means.
public struct WatchWeights: Equatable, Sendable {
    private let byPath: [String: Double]

    /// No corpus is the honest state before the first fetch lands: every clip
    /// weighs the same, so the draw is an ordinary uniform shuffle.
    public init(sidecars: [String: Sidecar] = [:]) {
        byPath = sidecars.compactMapValues { $0.watchWeight }
    }

    public func weight(for path: String) -> Double {
        byPath[path] ?? 1.0
    }
}

/// The two random primitives the shuffle is built from, kept apart from the
/// weights so they can be reasoned about — and seeded — on their own.
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
    /// primitives above are written against.
    private static func uniform(_ rng: inout some RandomNumberGenerator) -> Double {
        Double(rng.next() >> 11) * 0x1p-53
    }
}
