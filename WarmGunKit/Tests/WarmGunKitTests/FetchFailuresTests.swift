import Testing
@testable import WarmGunKit

@Suite struct FetchFailuresTests {
    @Test func theAwaitedVideoIsSkippedOnItsThirdRefusalAndAFifthSkipInARowHoldsTheRun() {
        var failures = FetchFailures()
        let answers = [1, 2, 3, 3, 3, 3, 3, 3, 9].map { failures.failed(attempts: $0) }
        #expect(answers == [.keepWaiting, .keepWaiting, .skip, .skip, .skip, .skip, .skip, .hold, .hold])

        failures.fetched()
        let afterAVideoLands = failures.failed(attempts: 3)
        #expect(afterAVideoLands == .skip)
    }
}

extension FetchFailuresTests {
    @Test func theRunIsHeldFromTheFirstHoldUntilAVideoLands() {
        var failures = FetchFailures()
        for _ in 0..<5 { _ = failures.failed(attempts: 3) }
        #expect(!failures.holding)
        _ = failures.failed(attempts: 3)
        #expect(failures.holding)
        failures.fetched()
        #expect(!failures.holding)
    }
}
