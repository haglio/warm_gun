import Foundation

/// What a tap on the video means: the desktop satellite's four arrow keys, plus
/// the middle of the screen, which belongs to the controls rather than to a clip.
public enum TapAction: Equatable, Sendable {
    case previous, next, weird, lock, center
}

/// Where on the screen each gesture lives, decided here rather than in the view
/// so the mapping is testable without a device and identical wherever it is read.
public enum TapZones {
    /// A three-by-three reading of the tap: the outer columns are the whole
    /// height (next is the gesture of the run, so it wants the biggest target),
    /// and only the middle column splits into weird above, lock below, and the
    /// dead centre that opens the controls.
    ///
    /// A tap exactly on a dividing line belongs to the zone right of or below it,
    /// which keeps the zones half-open and every point in exactly one of them. A
    /// screen with no area yet reads as the centre: the controls sheet is the one
    /// gesture that costs nothing to open by accident.
    public static func action(x: Double, y: Double, width: Double, height: Double) -> TapAction {
        guard width > 0, height > 0 else { return .center }
        if x < width / 3 { return .previous }
        if x >= width * 2 / 3 { return .next }
        if y < height / 3 { return .weird }
        if y >= height * 2 / 3 { return .lock }
        return .center
    }
}
