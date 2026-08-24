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
        guard let original = LibraryPaths.parseOriginal(file.path),
              LibraryPaths.isVideo(file.path) else { return nil }
        path = file.path
        fileID = file.fileID
        size = file.size
        modified = file.modified
        duration = file.duration
        videoCodec = file.videoCodec
        width = file.width
        height = file.height
        source = original.source
        orientation = original.orientation
        stem = original.stem
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
