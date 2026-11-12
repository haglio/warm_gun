import Foundation

public struct GalleryRecords: Sendable {
    public let videosByKey: [String: String]

    public init(libraryPath: String, genauFlicksFolder: String?, videoPaths: [String]) {
        var videosByKey: [String: String] = [:]
        for video in videoPaths {
            if let key = Self.key(forVideo: video, libraryPath: libraryPath,
                                   genauFlicksFolder: genauFlicksFolder) { videosByKey[key] = video }
        }
        self.videosByKey = videosByKey
    }

    public func videosKeepingSidecars(of videoPaths: [String]) -> [String] {
        let kept = Set(videosByKey.values)
        return videoPaths.filter { !kept.contains($0) }
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

    private static func key(forVideo video: String, libraryPath: String, genauFlicksFolder: String?) -> String? {
        guard let path = libraryPathOf(video, libraryPath: libraryPath, genauFlicksFolder: genauFlicksFolder)
        else { return nil }
        return LibraryPaths.relativeToLibraryRoot(path, forLibrary: libraryPath)
    }

    private static func libraryPathOf(_ video: String, libraryPath: String, genauFlicksFolder: String?) -> String? {
        if video.hasPrefix(LibraryPaths.genauPrefix) {
            let inner = String(video.dropFirst(LibraryPaths.genauPrefix.count))
            guard isUnderAnAIFolder(inner), let folder = genauFlicksFolder,
                  let genau = LibraryPaths.genauPath(forLibrary: libraryPath) else { return nil }
            return genau + "/" + folder + "/" + inner
        }
        guard let kino = LibraryPaths.kinoPath(forLibrary: libraryPath),
              let upscale = LibraryPaths.upscalePath(forOriginal: video) else { return nil }
        return kino + "/" + upscale
    }

    private static func isUnderAnAIFolder(_ path: String) -> Bool {
        let folders = path.split(separator: "/")
        return zip(folders, folders.dropFirst()).contains { $0 == "2D" && $1 == "AI" }
    }
}
