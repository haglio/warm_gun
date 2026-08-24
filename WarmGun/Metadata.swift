import Compression
import Foundation
import WarmGunKit

/// Fetches the sidecar corpus — one getzip of the metadata mirror's AI branch
/// (1.5 MB for ~1,300 files) — and turns it into the path-keyed dictionary the
/// group index is built from. The zip walking lives in the Kit; only the raw
/// DEFLATE step is here, because it needs Apple's Compression framework.
enum MetadataFetcher {
    /// The zip in one call when the server will give it, one file at a time
    /// when it will not — either way the corpus arrives. `progress` narrates
    /// for the status line the sheet shows.
    static func fetchSidecars(client: PCloudClient, libraryPath: String,
                              listing: [LibraryFile],
                              progress: @escaping @Sendable (String) -> Void) async throws -> [String: Sidecar] {
        guard let metadataPath = LibraryPaths.metadataAIPath(forLibrary: libraryPath) else { return [:] }
        do {
            progress("fetching the metadata archive…")
            return try await fetchViaZip(client: client, metadataPath: metadataPath)
        } catch {
            // getzip has already failed against the real server once (it takes
            // a folderid, not a path) — never trust it as the only road.
            progress("archive failed — fetching sidecars singly…")
            return try await fetchSingly(client: client, listing: listing, progress: progress)
        }
    }

    /// One number standing for the whole mirror: how many sidecars, and the
    /// newest write among them. A matching fingerprint means nothing changed
    /// and there is nothing to fetch.
    static func fingerprint(of listing: [LibraryFile]) -> String {
        let newest = listing.map(\.modified.timeIntervalSince1970).max() ?? 0
        return "\(listing.count)|\(Int(newest))"
    }

    private static func fetchViaZip(client: PCloudClient, metadataPath: String) async throws -> [String: Sidecar] {
        guard let folderID = try await client.folderSkeleton(path: metadataPath, recursive: false).folderid else {
            throw ZipArchive.Failure(reason: "metadata folder has no id")
        }
        let body = try await client.downloadRaw(PCloudAPI.getZip(folderID: folderID, auth: ""), patientFirstByte: true)
        if body.first == UInt8(ascii: "{") {
            // pCloud answers errors as JSON even where a zip was asked for.
            _ = try PCloudAPI.decode(EmptyPayload.self, from: body)
        }
        let decoder = JSONDecoder()
        var sidecars: [String: Sidecar] = [:]
        for entry in try ZipArchive.entries(in: body, inflate: inflate) {
            guard let original = LibraryPaths.originalPath(forSidecarEntry: entry.name),
                  let sidecar = try? decoder.decode(Sidecar.self, from: entry.data) else { continue }
            sidecars[original] = sidecar
        }
        return sidecars
    }

    private static func fetchSingly(client: PCloudClient, listing: [LibraryFile],
                                    progress: @escaping @Sendable (String) -> Void) async throws -> [String: Sidecar] {
        let files = listing
        let decoder = JSONDecoder()
        var sidecars: [String: Sidecar] = [:]
        var fetched = 0
        try await withThrowingTaskGroup(of: (String, Data)?.self) { group in
            var iterator = files.makeIterator()
            var inFlight = 0
            func addNext(_ group: inout ThrowingTaskGroup<(String, Data)?, Error>) {
                guard let file = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard let url = try await client.fileLink(fileID: file.fileID).url else { return nil }
                    let tmp = try await client.download(url)
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    return (file.path, try Data(contentsOf: tmp))
                }
            }
            for _ in 0..<6 { addNext(&group) }
            while inFlight > 0 {
                guard let result = try await group.next() else { break }
                inFlight -= 1
                fetched += 1
                if fetched % 100 == 0 { progress("fetching sidecars \(fetched)/\(files.count)…") }
                if let (path, data) = result,
                   let original = LibraryPaths.originalPath(forSidecarEntry: path),
                   let sidecar = try? decoder.decode(Sidecar.self, from: data) {
                    sidecars[original] = sidecar
                }
                addNext(&group)
            }
        }
        return sidecars
    }

    struct EmptyPayload: Decodable {}

    /// Raw DEFLATE (zip method 8). Apple's ZLIB variant is exactly that — the
    /// headerless RFC 1951 stream zip entries carry.
    static func inflate(_ compressed: Data, _ uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return Data() }
        var out = Data(count: uncompressedSize)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            compressed.withUnsafeBytes { src -> Int in
                guard let d = dst.baseAddress, let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d.assumingMemoryBound(to: UInt8.self), uncompressedSize,
                                                 s, compressed.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == uncompressedSize ? out : nil
    }
}
