import Compression
import Foundation
import WarmGunKit

/// Fetches the sidecar corpus — one getzip of the metadata mirror's AI branch
/// (1.5 MB for ~1,300 files) — and turns it into the path-keyed dictionary the
/// group index is built from. The zip walking lives in the Kit; only the raw
/// DEFLATE step is here, because it needs Apple's Compression framework.
enum MetadataFetcher {
    static func fetchSidecars(client: PCloudClient, libraryPath: String) async throws -> [String: Sidecar] {
        guard let metadataPath = LibraryPaths.metadataAIPath(forLibrary: libraryPath) else { return [:] }
        let body = try await client.downloadRaw(PCloudAPI.getZip(path: metadataPath, auth: ""))
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
