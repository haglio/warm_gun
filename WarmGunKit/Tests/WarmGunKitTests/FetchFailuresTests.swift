import Testing
@testable import WarmGunKit

@Suite struct FetchFailuresTests {
    @Test func theAwaitedClipIsSkippedOnItsThirdRefusalAndAFifthSkipInARowHoldsTheRun() {
        // A dead network must leave the run parked and retrying, not sprint it
        // silently through the whole playlist.
        var failures = FetchFailures()
        let answers = [1, 2, 3, 3, 3, 3, 3, 3, 9].map { failures.failed(attempts: $0) }
        #expect(answers == [.keepWaiting, .keepWaiting, .skip, .skip, .skip, .skip, .skip, .hold, .hold])

        failures.fetched()
        let afterAClipLands = failures.failed(attempts: 3)
        #expect(afterAClipLands == .skip)
    }
}
