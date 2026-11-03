import Foundation

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

public extension LibraryFile {
    func prefixed(_ prefix: String) -> LibraryFile {
        LibraryFile(path: prefix + path, fileID: fileID, size: size, modified: modified,
                    duration: duration, videoCodec: videoCodec, width: width, height: height)
    }
}

public struct Video: Codable, Hashable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case path, fileID, size, modified, duration, videoCodec, width, height, source, stem
        case shape = "orientation"
    }

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
    public let shape: VideoShape
    public let stem: String

    public var streams: Bool { size > Self.streamThresholdBytes }

    private static let streamThresholdBytes: Int64 = 25_000_000

    init?(file: LibraryFile) {
        guard LibraryPaths.isVideo(file.path) else { return nil }
        if let original = LibraryPaths.parseOriginal(file.path) {
            source = original.source
            shape = original.shape
            stem = original.stem
        } else if file.path.hasPrefix(LibraryPaths.nonAIPrefix) {
            let inner = file.path.dropFirst(LibraryPaths.nonAIPrefix.count)
            let components = inner.split(separator: "/").map(String.init)
            guard let name = components.last, !components.dropLast().contains("processed") else { return nil }
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
            let bare = String(name[..<dot])
            guard !bare.hasSuffix(LibraryPaths.upscaleSuffix), !bare.hasSuffix("_apo8_iris2") else { return nil }
            source = "non_AI"
            if let w = file.width, let h = file.height {
                shape = h >= w ? .portrait : .landscape
            } else {
                shape = .landscape
            }
            stem = bare
        } else if file.path.hasPrefix(LibraryPaths.genauFlatPrefix) {
            source = "genau"
            if let w = file.width, let h = file.height {
                shape = h >= w ? .portrait : .landscape
            } else {
                shape = .portrait
            }
            guard let name = LibraryPaths.filename(ofVideo: file.path),
                  let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
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

public struct Catalog: Codable, Equatable, Sendable {
    public let videos: [Video]

    private enum CodingKeys: String, CodingKey {
        case videos = "clips"
    }

    public init(videos: [Video]) {
        self.videos = videos
    }

    public init(files: [LibraryFile]) {
        videos = files.compactMap(Video.init(file:))
    }
}
