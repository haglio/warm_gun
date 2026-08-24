import Foundation

/// One file as the listing reported it: where it sits relative to the library
/// root, and what pCloud already knows about it (so nothing is ever probed).
public struct LibraryFile: Equatable, Sendable {
    public let path: String
    public let fileID: Int64
    public let size: Int64
    public let modified: Date
    public let duration: Double?
    public let videoCodec: String?
    public let width: Int?
    public let height: Int?

    public init(path: String, fileID: Int64, size: Int64, modified: Date,
                duration: Double?, videoCodec: String?, width: Int?, height: Int?) {
        self.path = path
        self.fileID = fileID
        self.size = size
        self.modified = modified
        self.duration = duration
        self.videoCodec = videoCodec
        self.width = width
        self.height = height
    }
}

/// A playable original, identified everywhere by its library-relative path.
public struct Clip: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let fileID: Int64
    public let size: Int64
    public let modified: Date
    public let duration: Double?
    public let videoCodec: String?
    public let width: Int?
    public let height: Int?
    public let source: String
    public let orientation: Orientation
    public let stem: String

    init?(file: LibraryFile) {
        guard LibraryPaths.isVideo(file.path) else { return nil }
        if let original = LibraryPaths.parseOriginal(file.path) {
            source = original.source
            orientation = original.orientation
            stem = original.stem
        } else if file.path.hasPrefix(LibraryPaths.genauPrefix) {
            // A genau loop: no orientation folder — its pixels decide when the
            // listing has them, and portrait stands in when it does not (the
            // browse lets genau loops through either way).
            source = "genau"
            if let w = file.width, let h = file.height {
                orientation = h >= w ? .portrait : .landscape
            } else {
                orientation = .portrait
            }
            let name = String(file.path.dropFirst(LibraryPaths.genauPrefix.count))
            guard !name.contains("/"), let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
            stem = String(name[..<dot])
        } else {
            return nil
        }
        path = file.path
        fileID = file.fileID
        size = file.size
        modified = file.modified
        duration = file.duration
        videoCodec = file.videoCodec
        width = file.width
        height = file.height
    }
}

/// The local index of the library: built once from a listing, persisted, and
/// the only thing a playlist rebuild ever reads.
public struct Catalog: Codable, Equatable, Sendable {
    public let clips: [Clip]

    public init(clips: [Clip]) {
        self.clips = clips
    }

    public init(files: [LibraryFile]) {
        clips = files.compactMap(Clip.init(file:))
    }
}
