import Foundation

public enum LoopMode: String, CaseIterable, Sendable {
    case all, single, seed, action

    public var isGroup: Bool { self == .seed || self == .action }
}

public enum LoopCycle {
    public static func next(after running: LoopMode, canLoop: (LoopMode) -> Bool) -> LoopMode {
        let stops = LoopMode.allCases
        let start = stops.firstIndex(of: running)! + 1
        for offset in 0..<stops.count {
            let stop = stops[(start + offset) % stops.count]
            if stop.isGroup, !canLoop(stop) { continue }
            return stop
        }
        return .all
    }

    public static func message(leaving running: LoopMode, for next: LoopMode) -> String? {
        running.isGroup && !next.isGroup ? "Loop off" : nil
    }
}
