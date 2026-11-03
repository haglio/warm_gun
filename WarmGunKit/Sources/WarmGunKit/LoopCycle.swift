import Foundation

public enum LoopMode: String, CaseIterable, Sendable {
    case all, single, seed, action
}

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
