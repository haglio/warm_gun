import Foundation

/// Which loop the run is in — the Loop control's four stops, in the order the
/// control draws them: the whole browse, one clip, the current clip's seed
/// family, its action group.
public enum LoopMode: String, CaseIterable, Sendable {
    case all, single, seed, action
}

/// The E key: one step clockwise around the Loop control, `all` → `single` →
/// `seed` → `action` → `all`. A group stop whose group holds only this clip
/// has no loop to offer and is stepped over; the one-clip loop always has.
public enum LoopCycle {
    public static func next(after running: LoopMode, canLoop: (LoopMode) -> Bool) -> LoopMode {
        let stops = LoopMode.allCases
        let start = stops.firstIndex(of: running)! + 1
        for offset in 0..<stops.count {
            let stop = stops[(start + offset) % stops.count]
            if stop == .seed || stop == .action, !canLoop(stop) { continue }
            return stop
        }
        return .all
    }
}
