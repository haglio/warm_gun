import Foundation
import Testing
@testable import WarmGunKit

@Suite struct WatchStatsTests {
    /// The desktop's curve: every three completions doubles a clip's frequency,
    /// every three skips halves it, and a lock counts triple — locking is the
    /// strongest thing a viewer can say about a clip.
    @Test func completionsRaiseTheWeightSkipsLowerItAndALockCountsTriple() {
        #expect(WatchStats.weight(of: WatchEntry(completions: 3)) == 2.0)
        #expect(WatchStats.weight(of: WatchEntry(skips: 3)) == 0.5)
        #expect(WatchStats.weight(of: WatchEntry(locks: 1)) > WatchStats.weight(of: WatchEntry(completions: 1)))
    }
}

extension WatchStatsTests {
    /// The clamp is what keeps one adored clip from crowding the playlist out:
    /// nine points of score is the top of the curve and nothing beyond it moves.
    @Test func theWeightIsClampedToAnEighthAndEightfold() {
        #expect(WatchStats.weight(of: WatchEntry(completions: 9)) == 8.0)
        #expect(WatchStats.weight(of: WatchEntry(completions: 100, locks: 50)) == 8.0)
        #expect(WatchStats.weight(of: WatchEntry(skips: 9)) == 0.125)
        #expect(WatchStats.weight(of: WatchEntry(skips: 100)) == 0.125)
    }
}

extension WatchStatsTests {
    @Test func recordingEventsAccumulatesThemPerPath() {
        var stats = WatchStats()
        stats.record(.completion, path: "1_sorted/alpha/portrait/clip-one.mp4")
        stats.record(.completion, path: "1_sorted/alpha/portrait/clip-one.mp4")
        stats.record(.skip, path: "1_sorted/alpha/portrait/clip-one.mp4")
        stats.record(.lock, path: "1_sorted/alpha/portrait/clip-one.mp4")
        stats.record(.skip, path: "1_sorted/beta/landscape/clip-two.mp4")

        #expect(stats.entries["1_sorted/alpha/portrait/clip-one.mp4"] == WatchEntry(completions: 2, skips: 1, locks: 1))
        #expect(stats.entries["1_sorted/beta/landscape/clip-two.mp4"] == WatchEntry(skips: 1))
    }
}

extension WatchStatsTests {
    @Test func aPathWeighsWhatItsOwnRecordSaysItDoes() {
        let stats = WatchStats(entries: ["1_sorted/alpha/portrait/clip-one.mp4": WatchEntry(completions: 3)])
        #expect(stats.weight(for: "1_sorted/alpha/portrait/clip-one.mp4") == 2.0)
        #expect(stats.weight(for: "1_sorted/beta/landscape/clip-two.mp4") == 1.0)
    }
}

extension WatchStatsTests {
    /// The counts outlive the app run — they are the phone's own store, so they
    /// have to survive a JSON round trip unchanged, keys and all.
    @Test func theWholeStoreSurvivesAJSONRoundTrip() throws {
        var stats = WatchStats()
        stats.record(.lock, path: "1_sorted/alpha/portrait/clip-one.mp4")
        stats.record(.skip, path: "1_sorted/beta/landscape/clip-two.mp4")

        let data = try JSONEncoder().encode(stats)
        #expect(try JSONDecoder().decode(WatchStats.self, from: data) == stats)
        #expect(try JSONDecoder().decode(WatchEvent.self, from: Data(#""lock""#.utf8)) == .lock)
    }
}

/// A seeded generator, so every ordering test asserts on one fixed draw rather
/// than on a distribution that could flake. SplitMix64 is four lines and needs
/// no state beyond the seed — the same stream on every machine and every run.
struct PlaylistSeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension WatchStatsTests {
    /// Inclusion is the continuous version of marking a clip weird: a clip at or
    /// above neutral always makes the build, and one below it sits out in
    /// proportion to how far below it has fallen.
    @Test func inclusionKeepsEveryNeutralOrLovedClipAndThinsTheRest() {
        var rng = PlaylistSeededRNG(seed: 3)
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 1.0, rng: &rng) })
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 8.0, rng: &rng) })

        let kept = (0..<200).filter { _ in Weighting.passesInclusion(weight: 0.5, rng: &rng) }.count
        #expect(kept > 60 && kept < 140)
        #expect(!(0..<200).contains { _ in Weighting.passesInclusion(weight: 0.0, rng: &rng) })
    }
}

extension WatchStatsTests {
    /// A shuffle reorders; it never gains or loses a clip — with equal weights
    /// it is exactly a uniform shuffle of the same set.
    @Test func theWeightedShuffleKeepsEveryItemAndAcceptsAnEmptyList() {
        var rng = PlaylistSeededRNG(seed: 1)
        let stems = (0..<10).map { "clip-\($0)" }

        let shuffled = Weighting.weightedShuffle(stems, weight: { _ in 1.0 }, rng: &rng)

        #expect(shuffled.sorted() == stems.sorted())
        #expect(Weighting.weightedShuffle([String](), weight: { _ in 1.0 }, rng: &rng).isEmpty)
    }
}

extension WatchStatsTests {
    /// The point of the weighting: over many builds the loved clip is the one
    /// that opens the playlist far more often than the chronically skipped one.
    @Test func theWeightedShuffleFrontLoadsTheHeavierItem() {
        var rng = PlaylistSeededRNG(seed: 7)
        let weights = ["clip-heavy": 8.0, "clip-light": 0.125]

        let heavyFirst = (0..<200).filter { _ in
            Weighting.weightedShuffle(["clip-light", "clip-heavy"], weight: { weights[$0]! }, rng: &rng).first == "clip-heavy"
        }.count

        #expect(heavyFirst > 150)
    }
}

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

extension WatchStatsTests {
    @Test func aPartialPersistedEntryDecodesWithTheMissingCountsAtZero() throws {
        // The desktop reads its stats rows with `entry.get(field, 0)`; a row
        // written before a count existed (or trimmed by hand) must land at zero,
        // not throw the whole stats file away.
        let old = Data(#"{"entries":{"1_sorted/alpha/portrait/clip-one.mp4":{"locks":2}}}"#.utf8)
        let stats = try JSONDecoder().decode(WatchStats.self, from: old)
        let entry = try #require(stats.entries["1_sorted/alpha/portrait/clip-one.mp4"])
        #expect(entry == WatchEntry(completions: 0, skips: 0, locks: 2))
    }
}

extension WatchStatsTests {
    @Test func backwardJitterOnTheSameClipIsNotAWrap() {
        // Only a fall of more than half the clip reads as the loop starting
        // over; scrubbing or stutter a few frames back must not count a play.
        var tracker = WatchTracker()
        let path = "1_sorted/alpha/portrait/clip-one.mp4"
        _ = tracker.sample(path: path, fraction: 0.90, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: path, fraction: 0.86, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }

    @Test func aWrapOnAClipNeverWatchedThroughCountsNothing() {
        // The loop restarting only speaks for a play when the run actually
        // reached the completion mark first.
        var tracker = WatchTracker()
        let path = "1_sorted/alpha/portrait/clip-one.mp4"
        _ = tracker.sample(path: path, fraction: 0.55, now: Date(timeIntervalSince1970: 0))
        let events = tracker.sample(path: path, fraction: 0.02, now: Date(timeIntervalSince1970: 1))
        #expect(events.isEmpty)
    }
}

extension WatchStatsTests {
    @Test func aWeightThatIsNotAPositiveNumberShufflesAsNeutral() {
        // The desktop coerces a dead weight to 1.0 before drawing; a negative or
        // non-finite one from a foreign caller must not front-load the item (a
        // negative key sorts first — the exact inverse of the intent).
        var rng = PlaylistSeededRNG(seed: 3)
        var leads = 0
        for _ in 0..<200 {
            let order = Weighting.weightedShuffle(["a", "b", "c", "d"],
                                                  weight: { $0 == "d" ? -1.0 : 1.0 }, rng: &rng)
            if order.first == "d" { leads += 1 }
        }
        #expect((20...80).contains(leads))  // ~1 in 4 of 200; -1.0 raw would be 200 of 200
    }
}
