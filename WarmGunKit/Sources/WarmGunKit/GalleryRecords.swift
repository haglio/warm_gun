import Foundation

public struct GalleryRecords: Sendable {
    public let videosByKey: [String: String]

    public init(libraryPath: String, genauFlicksFolder: String?, videoPaths: [String]) {
        var videosByKey: [String: String] = [:]
        for video in videoPaths {
            if let key = Self.key(forVideo: video, libraryPath: libraryPath) { videosByKey[key] = video }
        }
        self.videosByKey = videosByKey
    }

    public func records(in file: Data) -> [String: Data] {
        guard let entries = (try? JSONSerialization.jsonObject(with: file)) as? [String: Any] else { return [:] }
        var records: [String: Data] = [:]
        for (key, video) in videosByKey {
            guard let entry = entries[key] as? [String: Any],
                  let record = try? JSONSerialization.data(withJSONObject: entry) else { continue }
            records[video] = record
        }
        return records
    }

    private static func key(forVideo video: String, libraryPath: String) -> String? {
        guard let kino = LibraryPaths.kinoPath(forLibrary: libraryPath),
              let upscale = LibraryPaths.upscalePath(forOriginal: video) else { return nil }
        return LibraryPaths.relativeToLibraryRoot(kino + "/" + upscale, forLibrary: libraryPath)
    }
}
