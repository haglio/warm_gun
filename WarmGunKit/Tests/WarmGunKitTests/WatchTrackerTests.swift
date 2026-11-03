import Foundation
import Testing
@testable import WarmGunKit

@Suite struct WatchTrackerTests {
    static let one = "1_sorted/alpha/portrait/video-one.mp4"
    static let two = "1_sorted/beta/landscape/video-two.mp4"
    static let start = Date(timeIntervalSince1970: 1_000)

    @Test func aVideoWatchedToTheEndCountsACompletionWhenItDeparts() {
        var tracker = WatchTracker()
        #expect(tracker.sample(path: Self.one, fraction: 0.1, now: Self.start).isEmpty)
        #expect(tracker.sample(path: Self.one, fraction: 0.9, now: Self.start + 4).isEmpty)

        let events = tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 8)

        #expect(events.map(\.event) == [.completion])
        #expect(events.map(\.path) == [Self.one])
    }
}

extension WatchTrackerTests {
    @Test func eachRepeatOneWrapOfAHeldVideoCountsAnotherCompletion() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.5, now: Self.start)
        #expect(tracker.sample(path: Self.one, fraction: 0.9, now: Self.start + 1).isEmpty)
        #expect(tracker.sample(path: Self.one, fraction: 0.99, now: Self.start + 2).isEmpty)

        let firstWrap = tracker.sample(path: Self.one, fraction: 0.02, now: Self.start + 3)
        #expect(firstWrap.map(\.event) == [.completion])
        #expect(firstWrap.map(\.path) == [Self.one])

        #expect(tracker.sample(path: Self.one, fraction: 0.95, now: Self.start + 6).isEmpty)
        #expect(tracker.sample(path: Self.one, fraction: 0.02, now: Self.start + 7).map(\.event) == [.completion])
    }
}

extension WatchTrackerTests {
    @Test func aTapAwayFromAVideoBarelyStartedCountsASkip() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.2, now: Self.start)
        tracker.noteUserNav(now: Self.start + 5)

        let events = tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 5.5)

        #expect(events.map(\.event) == [.skip])
        #expect(events.map(\.path) == [Self.one])
    }
}

extension WatchTrackerTests {
    @Test func aDiscardSwallowsOnlyTheDepartureItPrecedes() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.95, now: Self.start)
        tracker.noteUserNav(now: Self.start + 1)
        tracker.noteDiscard()

        #expect(tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 1).isEmpty)

        _ = tracker.sample(path: Self.two, fraction: 0.95, now: Self.start + 5)
        #expect(tracker.sample(path: Self.one, fraction: 0.0, now: Self.start + 9).map(\.path) == [Self.two])
    }
}

extension WatchTrackerTests {
    @Test func aDepartureIsNeutralWithoutARecentTapOrPastTheSkipMark() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.2, now: Self.start)
        #expect(tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 60).isEmpty)

        var late = WatchTracker()
        _ = late.sample(path: Self.one, fraction: 0.7, now: Self.start)
        late.noteUserNav(now: Self.start)
        #expect(late.sample(path: Self.two, fraction: 0.0, now: Self.start + 1).isEmpty)
    }
}

extension WatchTrackerTests {
    @Test func backwardJitterOnTheSameVideoIsNotAWrap() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.90, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: Self.one, fraction: 0.86, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }

    @Test func aWrapOnAVideoNeverWatchedThroughCountsNothing() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.55, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: Self.one, fraction: 0.02, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }
}

extension WatchTrackerTests {
    @Test func theEventNamesAreTheWordsTheDesktopCounts() {
        #expect(WatchEvent.completion.rawValue == "completion")
        #expect(WatchEvent.skip.rawValue == "skip")
        #expect(WatchEvent.lock.rawValue == "lock")
    }
}
