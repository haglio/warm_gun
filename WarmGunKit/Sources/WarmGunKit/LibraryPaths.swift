import Foundation

/// Which way a video is filed — by folder, never by its pixels: 21 videos in the
/// library are square and live wherever the sorter put them.
public enum VideoShape: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

/// The shape of the AI library, relative to its root (`.../videos/videos/2D/AI`).
///
/// Every video exists twice: the original under `1_sorted/<source>/<shape>/`
/// and the Topaz upscale under `2_outbox/upscaled_by_orientation/<shape>/<source>/`
/// with `_topaz` on the stem — note the two trees nest source and shape
/// the opposite way round. Warm Gun plays the originals and names the upscales
/// only to talk to the desktop (favorites, trash), which knows videos by those.
public enum LibraryPaths {
    public struct Original: Equatable, Sendable {
        public let source: String
        public let shape: VideoShape
        public let stem: String
    }

    public static func parseOriginal(_ path: String) -> Original? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "1_sorted",
              let shape = VideoShape(rawValue: parts[2]) else { return nil }
        let file = parts[3]
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return nil }
        return Original(source: parts[1], shape: shape, stem: String(file[..<dot]))
    }

    /// What the desktop satellite builder accepts (`fun_time/modes.py:27`).
    public static let videoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "m4v"]

    public static func isVideo(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return false }
        return videoExtensions.contains(path[path.index(after: dot)...].lowercased())
    }

    public static let upscaleSuffix = "_topaz"
    public static let upscaledRoot = "2_outbox/upscaled_by_orientation"
    public static let trashDir = "2_outbox/trash"

    /// The desktop's name for the same video: what the trash gesture moves.
    public static func upscalePath(forOriginal path: String) -> String? {
        guard let o = parseOriginal(path) else { return nil }
        return "\(upscaledRoot)/\(o.shape.rawValue)/\(o.source)/\(o.stem)\(upscaleSuffix).mp4"
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

    private static func replacingLastFolders(_ count: Int, of path: String, with name: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > count else { return nil }
        return "/" + (parts.dropLast(count) + [name]).joined(separator: "/")
    }

    public static func genauPath(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(2, of: libraryPath, with: "genau")
    }

    /// What the folder holding Genau's flicks is called is the account's own
    /// vocabulary, like the library's path, so it is found by its skeleton.
    public static func genauFlicksFolder(in genau: PCloudEntry) -> String? {
        let fitting = (genau.contents ?? []).filter { folder in
            folder.isfolder && folder.name != genauTrashFolder
                && (folder.contents ?? []).contains { $0.isfolder && $0.name == "2D" }
        }
        return fitting.count == 1 ? fitting[0].name : nil
    }

    static let genauTrashFolder = "trash"

    /// The prefix the app files Genau's flicks under in its own catalog paths.
    public static let genauPrefix = "genau/clips/"

    /// Where the 2D videos are under that prefix -- the ones a phone plays.
    public static let genauFlatPrefix = genauPrefix + "2D/"

    /// *entries* with each one named the way Genau's flicks folder named a flick
    /// before it split into 2D and VR — `genau/clips/<file>` — renamed to the
    /// one entry of *current* that ends in that same file name. One that
    /// matches none, or more than one, is left as it was.
    public static func rekeyedFlatGenau(_ entries: Set<String>, against current: Set<String>) -> Set<String> {
        var byFileName: [String: [String]] = [:]
        for entry in current where entry.hasPrefix(genauPrefix) {
            guard let name = entry.split(separator: "/").last.map(String.init) else { continue }
            byFileName[name, default: []].append(entry)
        }
        return Set(entries.map { entry in
            guard entry.hasPrefix(genauPrefix) else { return entry }
            let rest = String(entry.dropFirst(genauPrefix.count))
            guard !rest.isEmpty, !rest.contains("/"),
                  let matches = byFileName[rest], matches.count == 1 else { return entry }
            return matches[0]
        })
    }

    /// The non-AI library — the real scenes, full videos and the videos cut
    /// out of them — beside the AI folder: `2D/non_AI`.
    public static func nonAIPath(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(1, of: libraryPath, with: "non_AI")
    }

    /// The prefix the app files non-AI scenes under in its own catalog paths.
    public static let nonAIPrefix = "non_AI/"

    /// The metadata mirror's root — `videos/metadata`, the videos tree's
    /// sibling, reached from the folder holding both.
    public static func metadataRoot(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(3, of: libraryPath, with: "metadata")
    }

    /// One tree of the metadata mirror, one lane of the library.
    ///
    /// The mirror parallels the video tree path for path with the extension
    /// swapped for `.json` (`evolver/util/sidecar.py`), which makes two of the
    /// three lanes a straight translation. The AI lane is the exception: Fun
    /// Time plays the UPSCALE, so that is where the sidecar is keyed, and the
    /// upscale tree nests shape above source where `1_sorted` nests
    /// source above shape. There is no `metadata/2D/AI/1_sorted` tree at
    /// all — a generated video's own path names no sidecar.
    public enum MetadataBranch: String, CaseIterable, Sendable {
        case ai
        case genau
        case nonAI

        /// The pCloud folder this branch's sidecars live in.
        public func path(forLibrary libraryPath: String, genauFlicksFolder: String?) -> String? {
            guard let root = LibraryPaths.metadataRoot(forLibrary: libraryPath) else { return nil }
            switch self {
            case .ai: return root + "/2D/AI"
            case .genau: return genauFlicksFolder.map { root + "/genau/" + $0 }
            case .nonAI: return root + "/2D/non_AI"
            }
        }

        /// Where *videoPath*'s sidecar sits inside this branch — relative to the
        /// branch folder and WITHOUT the `.json`, because the mirror drops the
        /// video's own extension and a real scene is not always an `.mp4`.
        /// Nil when the video belongs to another lane.
        public func sidecarPath(forVideo videoPath: String) -> String? {
            switch self {
            case .ai:
                guard let original = LibraryPaths.parseOriginal(videoPath) else { return nil }
                return "\(LibraryPaths.upscaledRoot)/\(original.shape.rawValue)"
                    + "/\(original.source)/\(original.stem)\(LibraryPaths.upscaleSuffix)"
            case .genau:
                guard videoPath.hasPrefix(LibraryPaths.genauPrefix) else { return nil }
                return LibraryPaths.dropExtension(
                    String(videoPath.dropFirst(LibraryPaths.genauPrefix.count)))
            case .nonAI:
                guard videoPath.hasPrefix(LibraryPaths.nonAIPrefix) else { return nil }
                let inner = String(videoPath.dropFirst(LibraryPaths.nonAIPrefix.count))
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
    public static func filename(ofVideo path: String) -> String? {
        guard let last = path.split(separator: "/", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return nil }
        return String(last)
    }

    /// What a favorite is filed under.
    ///
    /// A generated video is filed under its STEM, because its original and its
    /// upscale share it, and because `1_sorted` and `2_outbox` are in
    /// total correspondence the stem is unique across that lane. Nothing makes
    /// the same promise for the other two: the non-AI tree is walked
    /// recursively on both sides, and Genau's folder holds flicks carved by
    /// hand beside generated ones, so two same-named files are perfectly
    /// possible. Those are filed under their whole path, which the library
    /// itself keeps unique — so one star can never cover two videos.
    public static func favoriteKey(forVideo path: String) -> String? {
        if let original = parseOriginal(path) { return original.stem }
        guard path.hasPrefix(genauPrefix) || path.hasPrefix(nonAIPrefix) else { return nil }
        return dropExtension(path)
    }
}
