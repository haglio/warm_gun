import Foundation

/// Which way a clip is filed — by folder, never by its pixels: 21 clips in the
/// library are square and live wherever the sorter put them.
public enum Orientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

/// The shape of the AI library, relative to its root (`.../videos/videos/2D/AI`).
///
/// Every clip exists twice: the original under `1_sorted/<source>/<orientation>/`
/// and the Topaz upscale under `2_outbox/upscaled_by_orientation/<orientation>/<source>/`
/// with `_topaz` on the stem — note the two trees nest source and orientation
/// the opposite way round. Warm Gun plays the originals and names the upscales
/// only to talk to the desktop (favorites, weird), which knows clips by those.
public enum LibraryPaths {
    public struct Original: Equatable, Sendable {
        public let source: String
        public let orientation: Orientation
        public let stem: String
    }

    public static func parseOriginal(_ path: String) -> Original? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "1_sorted",
              let orientation = Orientation(rawValue: parts[2]) else { return nil }
        let file = parts[3]
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return nil }
        return Original(source: parts[1], orientation: orientation, stem: String(file[..<dot]))
    }

    /// What the desktop satellite builder accepts (`fun_time/modes.py:27`).
    public static let videoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "m4v"]

    public static func isVideo(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return false }
        return videoExtensions.contains(path[path.index(after: dot)...].lowercased())
    }

    public static let upscaleSuffix = "_topaz"
    public static let upscaledRoot = "2_outbox/upscaled_by_orientation"
    /// Where a clip marked weird is parked until Evolver purges it, along with
    /// its original and its sidecar, on the desktop's next run.
    public static let weirdDir = "2_outbox/kinda_weird"

    /// The desktop's name for the same clip: what `favs.csv` stores and what the
    /// weird gesture moves.
    public static func upscalePath(forOriginal path: String) -> String? {
        guard let o = parseOriginal(path) else { return nil }
        return "\(upscaledRoot)/\(o.orientation.rawValue)/\(o.source)/\(o.stem)\(upscaleSuffix).mp4"
    }

    /// The stem of a clip named the desktop's way — a path (Windows or POSIX, any
    /// prefix) to `<stem>_topaz.<ext>` — or nil when it is not an upscale name.
    /// The stem alone identifies a clip: they are unique library-wide.
    public static func stem(ofUpscaleReference reference: String) -> String? {
        let file = reference.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? reference
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return nil }
        let stem = String(file[..<dot])
        guard stem.hasSuffix(upscaleSuffix) else { return nil }
        return String(stem.dropLast(upscaleSuffix.count))
    }
}
