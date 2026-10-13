import Testing
@testable import WarmGunKit

/// The desktop's E key, one step around seed, action and off.
struct LoopCycleTests {
    @Test func nothingRunningStartsASeedLoop() {
        #expect(LoopCycle.step(running: nil, locked: false, canLoop: { _ in true }) == .loop(.seed))
    }
}

extension LoopCycleTests {
    @Test func aSeedLoopStepsOnToTheActionLoop() {
        #expect(LoopCycle.step(running: .seed, locked: false, canLoop: { _ in true }) == .loop(.action))
    }
}

extension LoopCycleTests {
    @Test func anActionLoopStepsOnToOff() {
        #expect(LoopCycle.step(running: .action, locked: false, canLoop: { _ in true }) == .off)
    }
}

extension LoopCycleTests {
    @Test func anAxisWhoseGroupIsThisClipAloneIsSteppedOver() {
        #expect(LoopCycle.step(running: nil, locked: false, canLoop: { $0 == .action }) == .loop(.action))
    }
}

extension LoopCycleTests {
    @Test func aSeedLoopWithNoActionGroupStepsStraightToOff() {
        #expect(LoopCycle.step(running: .seed, locked: false, canLoop: { $0 == .seed }) == .off)
    }
}

extension LoopCycleTests {
    @Test func withNoGroupToLoopThePressLocksTheClip() {
        #expect(LoopCycle.step(running: nil, locked: false, canLoop: { _ in false }) == .lock)
    }
}

extension LoopCycleTests {
    @Test func andTheNextPressLetsItGo() {
        #expect(LoopCycle.step(running: nil, locked: true, canLoop: { _ in false }) == .unlock)
    }
}
