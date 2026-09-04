import Foundation
import Testing
@testable import WarmGunKit

/// The tracker is fed position samples and classifies what it sees, so every
/// test here reads as a little playback session against a fixed clock.
@Suite struct WatchTrackerTests {
    static let one = "1_sorted/alpha/portrait/clip-one.mp4"
    static let two = "1_sorted/beta/landscape/clip-two.mp4"
    static let start = Date(timeIntervalSince1970: 1_000)

    /// Reaching the end and rolling on is a watch, however the roll-on happened:
    /// the first sample of a clip only starts tracking it.
    @Test func aClipWatchedToTheEndCountsACompletionWhenItDeparts() {
        var tracker = WatchTracker()
        #expect(tracker.sample(path: Self.one, fraction: 0.1, now: Self.start).isEmpty)
        #expect(tracker.sample(path: Self.one, fraction: 0.9, now: Self.start + 4).isEmpty)

        let events = tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 8)

        #expect(events.map(\.event) == [.completion])
        #expect(events.map(\.path) == [Self.one])
    }
}

extension WatchTrackerTests {
    /// A locked clip never departs, so the only evidence it was watched is the
    /// position jumping back to the top: a satellite has no seek control, so a
    /// big backward jump from near the end can only be a repeat-one wrap, and
    /// each wrap is one more full watch.
    @Test func eachRepeatOneWrapOfAHeldClipCountsAnotherCompletion() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.5, now: Self.start)
        #expect(tracker.sample(path: Self.one, fraction: 0.9, now: Self.start + 1).isEmpty)
        // Still running: playing on past the mark says nothing on its own.
        #expect(tracker.sample(path: Self.one, fraction: 0.99, now: Self.start + 2).isEmpty)

        let firstWrap = tracker.sample(path: Self.one, fraction: 0.02, now: Self.start + 3)
        #expect(firstWrap.map(\.event) == [.completion])
        #expect(firstWrap.map(\.path) == [Self.one])

        #expect(tracker.sample(path: Self.one, fraction: 0.95, now: Self.start + 6).isEmpty)
        #expect(tracker.sample(path: Self.one, fraction: 0.02, now: Self.start + 7).map(\.event) == [.completion])
    }
}

extension WatchTrackerTests {
    /// A tap that jumps off a clip barely started is the one thing that counts
    /// against it — the negative signal the shuffle thins clips out by.
    @Test func aTapAwayFromAClipBarelyStartedCountsASkip() {
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.2, now: Self.start)
        tracker.noteUserNav(now: Self.start + 5)

        let events = tracker.sample(path: Self.two, fraction: 0.0, now: Self.start + 5.5)

        #expect(events.map(\.event) == [.skip])
        #expect(events.map(\.path) == [Self.one])
    }
}

extension WatchTrackerTests {
    /// A clip marked weird leaves the playlist mid-play, which looks exactly
    /// like a skip and would otherwise punish a clip the viewer has already
    /// passed a harder judgement on. The discard swallows that one departure
    /// and nothing after it.
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
    /// An early departure nobody asked for — the automatic advance after an
    /// unlock, a clip that went away — must not punish the clip; and leaving
    /// late but unfinished is neither a watch nor a skip.
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
    @Test func backwardJitterOnTheSameClipIsNotAWrap() {
        // Only a fall of more than half the clip reads as the loop starting
        // over; scrubbing or stutter a few frames back must not count a play.
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.90, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: Self.one, fraction: 0.86, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }

    @Test func aWrapOnAClipNeverWatchedThroughCountsNothing() {
        // The loop restarting only speaks for a play when the run actually
        // reached the completion mark first.
        var tracker = WatchTracker()
        _ = tracker.sample(path: Self.one, fraction: 0.55, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: Self.one, fraction: 0.02, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }
}

extension WatchTrackerTests {
    /// The journal spells an event with the enum's raw value and the desktop
    /// stage counts by that exact word, so these three strings are a contract
    /// with another repository rather than labels this side may rename.
    @Test func theEventNamesAreTheWordsTheDesktopCounts() {
        #expect(WatchEvent.completion.rawValue == "completion")
        #expect(WatchEvent.skip.rawValue == "skip")
        #expect(WatchEvent.lock.rawValue == "lock")
    }
}
