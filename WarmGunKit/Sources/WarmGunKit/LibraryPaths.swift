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

    /// The pCloud path of the library, found by its skeleton: the one folder
    /// holding both pipeline stages, `1_sorted` and `2_outbox`. The real path
    /// names are private to the account and never appear in code — discovery
    /// is what makes the library path a non-setting. Among several candidates
    /// (a parked copy under an underscore-prefixed folder, say), the live tree
    /// wins: no underscore component first, then the shallower, then the
    /// lexicographically first, so the answer is one value however the
    /// listing is ordered.
    public static func discoverLibrary(root: PCloudEntry, at basePath: String = "") -> String? {
        var candidates: [String] = []
        let base = basePath == "/" ? "" : basePath
        collectLibraryCandidates(root, at: base, into: &candidates)
        func parked(_ path: String) -> Bool {
            path.split(separator: "/").contains { $0.hasPrefix("_") }
        }
        func depth(_ path: String) -> Int {
            path.split(separator: "/").count
        }
        return candidates.min { a, b in
            (parked(a) ? 1 : 0, depth(a), a) < (parked(b) ? 1 : 0, depth(b), b)
        }
    }

    private static func collectLibraryCandidates(_ entry: PCloudEntry, at path: String,
                                                 into candidates: inout [String]) {
        guard entry.isfolder else { return }
        let children = entry.contents ?? []
        let names = Set(children.filter(\.isfolder).map(\.name))
        if names.contains("1_sorted") && names.contains("2_outbox") {
            candidates.append(path.isEmpty ? "/" : path)
        }
        for child in children where child.isfolder {
            collectLibraryCandidates(child, at: path + "/" + child.name, into: &candidates)
        }
    }

    /// Where Evolver delivers the genau loops: `videos/genau/clips`, a sibling
    /// of the `videos/videos` tree the library path points into — so it is
    /// reachable from the library path by construction, three components up.
    public static func genauClipsPath(forLibrary libraryPath: String) -> String? {
        let parts = libraryPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        return "/" + (parts.dropLast(3) + ["genau", "clips"]).joined(separator: "/")
    }

    /// The prefix the app files genau loops under in its own catalog paths.
    public static let genauPrefix = "genau/clips/"

    /// The non-AI library — the real scenes — beside the AI folder: "full
    /// length" in Fun Time's sense IS this tree, `2D/non_AI`.
    public static func nonAIPath(forLibrary libraryPath: String) -> String? {
        let parts = libraryPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return "/" + (parts.dropLast(1) + ["non_AI"]).joined(separator: "/")
    }

    /// The prefix the app files non-AI scenes under in its own catalog paths.
    public static let nonAIPrefix = "non_AI/"

    /// The AI branch of the metadata mirror — `videos/metadata/2D/AI`, the
    /// videos tree's sibling; its sidecars mirror the UPSCALE paths.
    public static func metadataAIPath(forLibrary libraryPath: String) -> String? {
        let parts = libraryPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        return "/" + (parts.dropLast(3) + ["metadata", "2D", "AI"]).joined(separator: "/")
    }

    /// The original a sidecar speaks for. Zip entries arrive as
    /// `2D/AI/2_outbox/upscaled_by_orientation/<orientation>/<source>/<stem>_topaz.json`
    /// — the upscale's path with `.json` — and the original sits at
    /// `1_sorted/<source>/<orientation>/<stem>.mp4`, source and orientation
    /// nested the other way round.
    public static func originalPath(forSidecarEntry entry: String) -> String? {
        // Anchored on the spine, not a fixed prefix: the zip's entry root
        // depends on what the server chose to zip.
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let spine = parts.firstIndex(of: "2_outbox"),
              parts.count == spine + 5, parts[spine + 1] == "upscaled_by_orientation",
              let orientation = Orientation(rawValue: parts[spine + 2]) else { return nil }
        let file = parts[spine + 4]
        guard file.hasSuffix(".json") else { return nil }
        let stem = String(file.dropLast(".json".count))
        guard stem.hasSuffix(upscaleSuffix) else { return nil }
        return "1_sorted/\(parts[spine + 3])/\(orientation.rawValue)/\(stem.dropLast(upscaleSuffix.count)).mp4"
    }

    /// The bare file name of a catalog path — what the controls overlay puts
    /// on the glass so the picture can be named. Nil when the path ends in a
    /// separator or is empty: there is no file there to name.
    public static func filename(ofClip path: String) -> String? {
        guard let last = path.split(separator: "/", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return nil }
        return String(last)
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
