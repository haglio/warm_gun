import Foundation

/// The two group axes a clip can be looped on: its seed family, or every
/// clip of its action.
public enum LoopAxis: Equatable, Sendable, CaseIterable {
    case seed, action
}

/// What one press of the desktop's E key does next.
public enum LoopStep: Equatable, Sendable {
    case loop(LoopAxis)
    case off
    case lock
    case unlock
}

/// The desktop satellite's loop cycle (`fun_time/satellite_groups.py`,
/// `loop_cycle`): one step around seed, action, off.
public enum LoopCycle {
    private static let cycle: [LoopAxis?] = [.seed, .action, nil]

    /// The next stop from *running* (nil when no group is looping). An axis
    /// whose group holds only this clip has no loop to offer and is stepped
    /// over; "off" is only a stop while something is on. When neither axis
    /// can loop, the press locks the clip, or lets a locked one go — a
    /// one-stop cycle would hold a clip the only key on it could not release.
    public static func step(running: LoopAxis?, locked: Bool, canLoop: (LoopAxis) -> Bool) -> LoopStep {
        let start = running.flatMap { cycle.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        for offset in 0..<cycle.count {
            guard let axis = cycle[(start + offset) % cycle.count] else {
                if running != nil { return .off }
                continue
            }
            if canLoop(axis) { return .loop(axis) }
        }
        return locked ? .unlock : .lock
    }
}
