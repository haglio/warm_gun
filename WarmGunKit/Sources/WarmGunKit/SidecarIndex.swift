import Foundation

public struct SidecarIndex: Sendable {
    public let videosByListedSidecar: [String: String]
    private let listedByName: [String: [String]]

    public init(branch: LibraryPaths.MetadataBranch, videoPaths: [String], listing: [String]) {
        var videoBySidecarPath: [String: String] = [:]
        for video in videoPaths {
            if let sidecar = branch.sidecarPath(forVideo: video) { videoBySidecarPath[sidecar] = video }
        }
        var wanted: [String: String] = [:]
        var byName: [String: [String]] = [:]
        for listed in listing {
            guard listed.hasSuffix(Self.suffix),
                  let video = videoBySidecarPath[String(listed.dropLast(Self.suffix.count))] else { continue }
            wanted[listed] = video
            byName[Self.name(of: listed), default: []].append(listed)
        }
        videosByListedSidecar = wanted
        listedByName = byName
    }

    public func video(forZipEntry entry: String) -> String? {
        for listed in listedByName[Self.name(of: entry)] ?? []
        where entry == listed || entry.hasSuffix("/" + listed) {
            return videosByListedSidecar[listed]
        }
        return nil
    }

    private static let suffix = ".json"

    private static func name(of path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }
}
