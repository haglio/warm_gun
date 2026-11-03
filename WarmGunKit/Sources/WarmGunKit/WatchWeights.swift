import Foundation

public struct WatchWeights: Equatable, Sendable {
    private let byPath: [String: Double]

    public init(sidecars: [String: Sidecar] = [:]) {
        byPath = sidecars.compactMapValues { $0.watchWeight }
    }

    public func weight(for path: String) -> Double {
        byPath[path] ?? 1.0
    }
}

public enum Weighting {
    public static func passesInclusion(weight: Double, rng: inout some RandomNumberGenerator) -> Bool {
        weight >= 1.0 || uniform(&rng) < weight
    }

    /// Efraimidis-Spirakis sampling: each item draws a key `-log(u)/w` and the list sorts ascending.
    public static func weightedShuffle<T>(_ items: [T], weight: (T) -> Double,
                                          rng: inout some RandomNumberGenerator) -> [T] {
        var keyed: [(item: T, key: Double)] = []
        keyed.reserveCapacity(items.count)
        for item in items {
            let w = weight(item)
            let safe = w.isFinite && w > 0 ? w : 1.0
            keyed.append((item, -log(max(uniform(&rng), 1e-12)) / safe))
        }
        return keyed.sorted { $0.key < $1.key }.map(\.item)
    }

    private static func uniform(_ rng: inout some RandomNumberGenerator) -> Double {
        Double(rng.next() >> 11) * 0x1p-53
    }
}
