import Testing
@testable import WarmGunKit

struct LoopCycleTests {
    @Test func noLoopStepsToLoopingTheOneVideo() {
        #expect(LoopCycle.next(after: .all, canLoop: { _ in true }) == .single)
    }
}

extension LoopCycleTests {
    @Test func theOneVideoLoopStepsToTheSeedLoop() {
        #expect(LoopCycle.next(after: .single, canLoop: { _ in true }) == .seed)
    }
}

extension LoopCycleTests {
    @Test func theSeedLoopStepsToTheActionLoop() {
        #expect(LoopCycle.next(after: .seed, canLoop: { _ in true }) == .action)
    }
}

extension LoopCycleTests {
    @Test func theActionLoopStepsBackToNoLoop() {
        #expect(LoopCycle.next(after: .action, canLoop: { _ in true }) == .all)
    }
}

extension LoopCycleTests {
    @Test func aSeedFamilyOfOneIsSteppedOver() {
        #expect(LoopCycle.next(after: .single, canLoop: { $0 == .action }) == .action)
    }
}

extension LoopCycleTests {
    @Test func anActionGroupOfOneIsSteppedOver() {
        #expect(LoopCycle.next(after: .seed, canLoop: { $0 == .seed }) == .all)
    }
}

extension LoopCycleTests {
    @Test func withNoGroupToLoopTheKeyIsATwoStopCycle() {
        #expect(LoopCycle.next(after: .single, canLoop: { _ in false }) == .all && LoopCycle.next(after: .all, canLoop: { _ in false }) == .single)
    }
}

extension LoopCycleTests {
    @Test func endingAGroupLoopSaysLoopOff() {
        #expect(LoopCycle.message(leaving: .seed, for: .all) == "Loop off")
        #expect(LoopCycle.message(leaving: .action, for: .single) == "Loop off")
    }
}

extension LoopCycleTests {
    @Test func leavingNoGroupLoopSaysNothing() {
        #expect(LoopCycle.message(leaving: .all, for: .all) == nil)
        #expect(LoopCycle.message(leaving: .single, for: .all) == nil)
        #expect(LoopCycle.message(leaving: .seed, for: .action) == nil)
    }
}
