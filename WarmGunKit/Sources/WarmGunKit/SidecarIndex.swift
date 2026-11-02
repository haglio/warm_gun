import Foundation

/// One branch of the metadata mirror, joined to the videos the phone plays.
///
/// The fetch has two roads — one zip of the whole branch, or the sidecars one
/// at a time — and both land on names that have to become catalog paths before
/// anything can use them. That translation is the whole of this type, so it can
/// be decided and tested without a network.
public struct SidecarIndex: Sendable {
    /// Every listed sidecar that speaks for a video in the catalog, keyed by the
    /// path the listing gave it (branch-relative, `.json` and all). Anything
    /// else in the branch — a sidecar for a video that has left the library, a
    /// file that is not a sidecar — is not worth a byte.
    public let videosByListedSidecar: [String: String]
    /// The same, keyed by file name, for matching a zip entry's tail.
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

    /// The video a zip entry speaks for. The archive's entries carry whatever
    /// root the server chose to zip under, which is not knowable from here, so
    /// an entry is matched by its TAIL against the paths the listing already
    /// gave — and the tail has to start on a separator, or a sidecar in one
    /// folder would answer for a same-named one in another.
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
