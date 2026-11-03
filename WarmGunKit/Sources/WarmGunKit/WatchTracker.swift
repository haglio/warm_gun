import Foundation

public enum WatchEvent: String, Sendable {
    case completion
    case skip
    case lock
}

public struct WatchTracker: Sendable {
    public static let completeFraction = 0.85
    public static let skipFraction = 0.60
    public static let navWindow: TimeInterval = 3.0
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

    public mutating func sample(path: String, fraction: Double, now: Date) -> [(event: WatchEvent, path: String)] {
        if path == self.path { return wrapped(to: fraction) }
        let departure = departureEvent(now: now)
        self.path = path
        maxFraction = max(0.0, fraction)
        suppressDeparted = false
        return departure.map { [$0] } ?? []
    }

    private mutating func wrapped(to fraction: Double) -> [(event: WatchEvent, path: String)] {
        guard !path.isEmpty, maxFraction >= Self.completeFraction,
              fraction < maxFraction - Self.wrapDrop else {
            maxFraction = max(maxFraction, fraction)
            return []
        }
        maxFraction = max(0.0, fraction)
        return [(.completion, path)]
    }

    private func departureEvent(now: Date) -> (event: WatchEvent, path: String)? {
        guard !path.isEmpty, !suppressDeparted else { return nil }
        if maxFraction >= Self.completeFraction { return (.completion, path) }
        let navRecent = now.timeIntervalSince(lastNavAt) <= Self.navWindow
        guard navRecent, maxFraction <= Self.skipFraction else { return nil }
        return (.skip, path)
    }
}
