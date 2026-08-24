import Testing
@testable import WarmGunKit

@Suite struct TapZonesTests {
    @Test func theOuterThirdsAreTheNavigationHalvesOfTheScreen() {
        #expect(TapZones.action(x: 40, y: 400, width: 390, height: 844) == .previous)
        #expect(TapZones.action(x: 350, y: 400, width: 390, height: 844) == .next)
    }
}

extension TapZonesTests {
    @Test func aTapOnADividingLineBelongsToTheZoneRightOfOrBelowIt() {
        // Half-open zones: every point on screen lands in exactly one of them,
        // so no tap can fall between two gestures.
        #expect(TapZones.action(x: 130, y: 400, width: 390, height: 844) == .center)
        #expect(TapZones.action(x: 260, y: 400, width: 390, height: 844) == .next)
        #expect(TapZones.action(x: 195, y: 844 / 3, width: 390, height: 844) == .center)
        #expect(TapZones.action(x: 195, y: 844 * 2 / 3, width: 390, height: 844) == .lock)
    }
}

extension TapZonesTests {
    @Test func aScreenWithNoAreaReadsAsTheCentre() {
        // The first taps can arrive before layout has a size; opening the
        // controls is the one gesture that undoes itself.
        #expect(TapZones.action(x: 0, y: 0, width: 0, height: 0) == .center)
        #expect(TapZones.action(x: 5, y: 5, width: -390, height: 844) == .center)
        #expect(TapZones.action(x: 5, y: 5, width: 390, height: -844) == .center)
    }
}

extension TapZonesTests {
    @Test func onlyTheMiddleColumnSplitsIntoWeirdAboveAndLockBelow() {
        #expect(TapZones.action(x: 195, y: 100, width: 390, height: 844) == .weird)
        #expect(TapZones.action(x: 195, y: 800, width: 390, height: 844) == .lock)
        #expect(TapZones.action(x: 195, y: 422, width: 390, height: 844) == .center)
    }
}
