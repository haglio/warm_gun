import Testing
@testable import WarmGunKit

/// The E key: one step clockwise around the Loop control's four stops.
struct LoopCycleTests {
    @Test func noLoopStepsToLoopingTheOneClip() {
        #expect(LoopCycle.next(after: .all, canLoop: { _ in true }) == .single)
    }
}

extension LoopCycleTests {
    @Test func theOneClipLoopStepsToTheSeedLoop() {
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
