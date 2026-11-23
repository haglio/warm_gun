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

    public static func noneForThisOne(_ group: LoopMode) -> String {
        "\(group.rawValue.capitalized) loop (none for this one)"
    }

    public static func message(stepping running: LoopMode, to next: LoopMode) -> String? {
        if let ending = message(leaving: running, for: next) { return ending }
        switch next {
        case .all: return "Loop: All"
        case .single: return "Loop: 1"
        case .seed, .action: return nil
        }
    }
}
