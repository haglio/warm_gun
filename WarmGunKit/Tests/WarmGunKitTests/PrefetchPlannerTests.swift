import Foundation
import Testing
@testable import WarmGunKit

@Suite struct PrefetchPlannerTests {
    /// A fabricated run of ten clips, numbered so a fetch order reads at a glance.
    static let ten = (0..<10).map { "1_sorted/alpha/portrait/clip-\($0).mp4" }

    @Test func fetchesTheClipOnScreenFirstAndThenTheOnesComingUp() {
        #expect(PrefetchPlanner.plan(playlist: Self.ten, index: 3, ahead: 2, behind: 0)
                == [Self.ten[3], Self.ten[4], Self.ten[5]])
    }
}

extension PrefetchPlannerTests {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func cached(_ index: Int, megabytes: Int64, usedAfter seconds: TimeInterval)
        -> PrefetchPlanner.CachedFile {
        PrefetchPlanner.CachedFile(path: ten[index], size: megabytes * 1_000_000,
                                   lastUsed: start.addingTimeInterval(seconds))
    }

    @Test func neverEvictsWhatTheWindowIsHoldingEvenWhenThatLeavesItOverTheCap() {
        // The window is what the next taps will play; deleting a clip inside it
        // to satisfy a cap would just fetch it again, and a cap set below the
        // window's own size is a setting to live with, not a reason to stall.
        let cached = [Self.cached(0, megabytes: 4, usedAfter: 0),
                      Self.cached(1, megabytes: 4, usedAfter: 60),
                      Self.cached(2, megabytes: 4, usedAfter: 120)]
        let keep: Set<String> = [Self.ten[0], Self.ten[1]]
        #expect(PrefetchPlanner.evictions(cached: cached, keep: keep, capBytes: 1_000_000)
                == [Self.ten[2]])
        #expect(PrefetchPlanner.evictions(cached: cached, keep: keep, capBytes: 12_000_000).isEmpty)
    }

    @Test func evictsTheLeastRecentlyPlayedUntilTheCacheIsUnderItsCap() {
        // Cached clips are keyed by file, so a reshuffle costs nothing; what
        // decides is how long ago each was last watched.
        let cached = [Self.cached(1, megabytes: 4, usedAfter: 60),
                      Self.cached(0, megabytes: 4, usedAfter: 0),
                      Self.cached(2, megabytes: 4, usedAfter: 120)]
        #expect(PrefetchPlanner.evictions(cached: cached, keep: [], capBytes: 8_000_000)
                == [Self.ten[0]])
    }
}

extension PrefetchPlannerTests {
    @Test func anEmptyRunAsksForNothing() {
        // Launch, before the index has been read: the planner runs anyway.
        #expect(PrefetchPlanner.plan(playlist: [], index: 0, ahead: 12, behind: 3).isEmpty)
    }
}

extension PrefetchPlannerTests {
    @Test func windowsThatRunPastTheEndsWrapAndStillNameEachClipOnce() {
        // The playlist is a ring, so a window deeper than the run itself would
        // otherwise ask for the same file several times over.
        let four = Array(Self.ten.prefix(4))
        #expect(PrefetchPlanner.plan(playlist: four, index: 3, ahead: 1, behind: 1)
                == [four[3], four[0], four[2]])
        let planned = PrefetchPlanner.plan(playlist: four, index: 0, ahead: 12, behind: 3)
        #expect(planned.count == four.count)
        #expect(Set(planned) == Set(four))
        #expect(planned.first == four[0])
    }
}

extension PrefetchPlannerTests {
    @Test func spendsTwoFetchesForwardForEveryOneBackward() {
        // Next is the gesture of the run and previous the exception, so the
        // window leans into the future without ever abandoning the past.
        let planned = PrefetchPlanner.plan(playlist: Self.ten, index: 4, ahead: 4, behind: 2)
        let offsets = planned.map { Self.ten.firstIndex(of: $0)! - 4 }
        #expect(offsets == [0, 1, 2, -1, 3, 4, -2])
    }
}

extension PrefetchPlannerTests {
    @Test(.timeLimit(.minutes(1))) func aWindowVastlyWiderThanTheRunCostsNoMoreThanTheRun() {
        // The plan is capped at the playlist's length — and so is the work: a
        // pathological window must not materialize millions of offsets first.
        let start = Date()
        let plan = PrefetchPlanner.plan(playlist: ["1_sorted/alpha/portrait/clip-one.mp4"],
                                        index: 0, ahead: 50_000_000, behind: 50_000_000)
        #expect(plan == ["1_sorted/alpha/portrait/clip-one.mp4"])
        #expect(Date().timeIntervalSince(start) < 0.05)
    }
}
