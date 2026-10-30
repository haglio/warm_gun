import Foundation

/// What the run does when the clip it is waiting on fails to download again.
public struct FetchFailures: Equatable, Sendable {
    public enum Answer: Equatable, Sendable {
        case keepWaiting, skip, hold
    }

    private var skippedInARow = 0

    public init() {}

    public mutating func failed(attempts: Int) -> Answer {
        guard attempts >= Self.refusalsBeforeSkipping else { return .keepWaiting }
        guard skippedInARow < Self.skipsBeforeHolding else { return .hold }
        skippedInARow += 1
        return .skip
    }

    public mutating func fetched() {
        skippedInARow = 0
    }

    private static let refusalsBeforeSkipping = 3
    private static let skipsBeforeHolding = 5
}
