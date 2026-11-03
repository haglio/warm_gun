import Foundation

public enum TapAction: Equatable, Sendable {
    case previous, next, trash, lock, center
}

public enum TapZones {
    public static func action(x: Double, y: Double, width: Double, height: Double) -> TapAction {
        guard width > 0, height > 0 else { return .center }
        if x < width / 3 { return .previous }
        if x >= width * 2 / 3 { return .next }
        if y < height / 3 { return .trash }
        if y >= height * 2 / 3 { return .lock }
        return .center
    }
}
