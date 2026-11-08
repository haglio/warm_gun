import Foundation

public struct SidecarIndex: Sendable {
    public let videosByListedSidecar: [String: String]

    public init(branch: LibraryPaths.MetadataBranch, videoPaths: [String], listing: [String]) {
        var videoBySidecarPath: [String: String] = [:]
        for video in videoPaths {
            if let sidecar = branch.sidecarPath(forVideo: video) { videoBySidecarPath[sidecar] = video }
        }
        var wanted: [String: String] = [:]
        for listed in listing {
            guard listed.hasSuffix(Self.suffix),
                  let video = videoBySidecarPath[String(listed.dropLast(Self.suffix.count))] else { continue }
            wanted[listed] = video
        }
        videosByListedSidecar = wanted
    }

    private static let suffix = ".json"
}
