import Foundation

public enum VideoShape: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

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

    public static let videoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "webm", "m4v"]

    public static func isVideo(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return false }
        return videoExtensions.contains(path[path.index(after: dot)...].lowercased())
    }

    public static let upscaleSuffix = "_topaz"
    public static let kinoUpscalesFolder = "2D/AI"
    public static let kinoTrashFolder = "trash"

    public static func kinoPath(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(2, of: libraryPath, with: "kino")
    }

    public static func upscalePath(forOriginal path: String) -> String? {
        guard let o = parseOriginal(path) else { return nil }
        return "\(kinoUpscalesFolder)/\(o.shape.rawValue)/\(o.source)/\(o.stem)\(upscaleSuffix).mp4"
    }

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
        if names.contains("0_inbox") && names.contains("1_sorted") {
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

    public static func genauFlicksFolder(in genau: PCloudEntry) -> String? {
        let fitting = (genau.contents ?? []).filter { folder in
            folder.isfolder && folder.name != genauTrashFolder
                && (folder.contents ?? []).contains { $0.isfolder && $0.name == "2D" }
        }
        return fitting.count == 1 ? fitting[0].name : nil
    }

    static let genauTrashFolder = "trash"

    public static let genauPrefix = "genau/clips/"

    public static let genauFlatPrefix = genauPrefix + "2D/"

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

    public static func nonAIPath(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(1, of: libraryPath, with: "non_AI")
    }

    public static let nonAIPrefix = "non_AI/"

    public static func metadataRoot(forLibrary libraryPath: String) -> String? {
        replacingLastFolders(3, of: libraryPath, with: "metadata")
    }

    public static func relativeToLibraryRoot(_ path: String, forLibrary libraryPath: String) -> String? {
        let rootDepth = libraryPath.split(separator: "/").count - 4
        guard rootDepth >= 0 else { return nil }
        return path.split(separator: "/").dropFirst(rootDepth).joined(separator: "/")
    }

    public enum MetadataBranch: String, CaseIterable, Sendable {
        case ai
        case genau
        case nonAI

        public func path(forLibrary libraryPath: String, genauFlicksFolder: String?) -> String? {
            guard let root = LibraryPaths.metadataRoot(forLibrary: libraryPath) else { return nil }
            switch self {
            case .ai: return root + "/kino/" + LibraryPaths.kinoUpscalesFolder
            case .genau: return genauFlicksFolder.map { root + "/genau/" + $0 }
            case .nonAI: return root + "/2D/non_AI"
            }
        }

        public func sidecarPath(forVideo videoPath: String) -> String? {
            switch self {
            case .ai:
                guard let original = LibraryPaths.parseOriginal(videoPath) else { return nil }
                return "\(original.shape.rawValue)/\(original.source)/\(original.stem)\(LibraryPaths.upscaleSuffix)"
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

    static func dropExtension(_ path: String) -> String? {
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return nil }
        let stem = String(path[..<dot])
        guard let last = stem.split(separator: "/", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return nil }
        return stem
    }

    public static func filename(ofVideo path: String) -> String? {
        guard let last = path.split(separator: "/", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return nil }
        return String(last)
    }

    public static func favoriteKey(forVideo path: String) -> String? {
        if let original = parseOriginal(path) { return original.stem }
        guard path.hasPrefix(genauPrefix) || path.hasPrefix(nonAIPrefix) else { return nil }
        return dropExtension(path)
    }
}
