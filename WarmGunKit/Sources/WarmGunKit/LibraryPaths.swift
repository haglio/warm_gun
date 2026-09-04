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

    /// The metadata mirror's root — `videos/metadata`, the videos tree's
    /// sibling, reached from the folder holding both.
    public static func metadataRoot(forLibrary libraryPath: String) -> String? {
        let parts = libraryPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        return "/" + (parts.dropLast(3) + ["metadata"]).joined(separator: "/")
    }

    /// One tree of the metadata mirror, one lane of the library.
    ///
    /// The mirror parallels the video tree path for path with the extension
    /// swapped for `.json` (`evolver/util/sidecar.py`), which makes two of the
    /// three lanes a straight translation. The AI lane is the exception: Fun
    /// Time plays the UPSCALE, so that is where the sidecar is keyed, and the
    /// upscale tree nests orientation above source where `1_sorted` nests
    /// source above orientation. There is no `metadata/2D/AI/1_sorted` tree at
    /// all — a generated clip's own path names no sidecar.
    public enum MetadataBranch: String, CaseIterable, Sendable {
        case ai
        case genau
        case nonAI

        /// The pCloud folder this branch's sidecars live in.
        public func path(forLibrary libraryPath: String) -> String? {
            guard let root = LibraryPaths.metadataRoot(forLibrary: libraryPath) else { return nil }
            switch self {
            case .ai: return root + "/2D/AI"
            // Not under 2D: the loops are delivered beside the library rather
            // than into it, and the mirror follows them there.
            case .genau: return root + "/genau/clips"
            case .nonAI: return root + "/2D/non_AI"
            }
        }

        /// Where *clipPath*'s sidecar sits inside this branch — relative to the
        /// branch folder and WITHOUT the `.json`, because the mirror drops the
        /// video's own extension and a real scene is not always an `.mp4`.
        /// Nil when the clip belongs to another lane.
        public func sidecarPath(forClip clipPath: String) -> String? {
            switch self {
            case .ai:
                guard let original = LibraryPaths.parseOriginal(clipPath) else { return nil }
                return "\(LibraryPaths.upscaledRoot)/\(original.orientation.rawValue)"
                    + "/\(original.source)/\(original.stem)\(LibraryPaths.upscaleSuffix)"
            case .genau:
                guard clipPath.hasPrefix(LibraryPaths.genauPrefix) else { return nil }
                let name = String(clipPath.dropFirst(LibraryPaths.genauPrefix.count))
                // The delivery is one flat folder; anything nested is not a loop.
                guard !name.contains("/") else { return nil }
                return LibraryPaths.dropExtension(name)
            case .nonAI:
                guard clipPath.hasPrefix(LibraryPaths.nonAIPrefix) else { return nil }
                let inner = String(clipPath.dropFirst(LibraryPaths.nonAIPrefix.count))
                guard !inner.isEmpty else { return nil }
                return LibraryPaths.dropExtension(inner)
            }
        }
    }

    /// A path with its file extension removed — nil when the last component has
    /// none, or is nothing but one.
    static func dropExtension(_ path: String) -> String? {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return nil }
        let stem = String(path[..<dot])
        guard let last = stem.split(separator: "/", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return nil }
        return stem
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
