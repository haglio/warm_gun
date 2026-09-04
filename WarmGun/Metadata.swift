import Compression
import Foundation
import WarmGunKit

/// Fetches the sidecar corpus — one getzip per branch of the metadata mirror,
/// with a one-file-at-a-time road when the server will not zip — and turns it
/// into the clip-keyed dictionary the group index, the weights and the
/// favorites are all read off. The zip walking lives in the Kit; only the raw
/// DEFLATE step is here, because it needs Apple's Compression framework.
enum MetadataFetcher {
    /// One branch as the survey found it: where it is, what it holds, and which
    /// of that speaks for a clip the phone can play.
    struct Branch {
        let path: String
        let files: [LibraryFile]
        let index: SidecarIndex
    }

    /// One cheap listing per branch. A branch that is absent or refuses to list
    /// simply contributes nothing — the corpus is still worth having without
    /// it, and the alternative is one missing folder costing every weight.
    static func survey(client: PCloudClient, libraryPath: String,
                       clipPaths: [String]) async -> [Branch] {
        var branches: [Branch] = []
        for branch in LibraryPaths.MetadataBranch.allCases {
            guard let path = branch.path(forLibrary: libraryPath),
                  let files = try? await client.listLibrary(path: path) else { continue }
            let index = SidecarIndex(branch: branch, clipPaths: clipPaths,
                                     listing: files.map(\.path))
            guard !index.clipsByListedSidecar.isEmpty else { continue }
            branches.append(Branch(path: path, files: files, index: index))
        }
        return branches
    }

    /// One number standing for the whole mirror: how many sidecars are worth
    /// having, and the newest write among everything listed. A matching
    /// fingerprint means nothing moved and there is nothing to fetch.
    static func fingerprint(of branches: [Branch]) -> String {
        branches.map { branch in
            let newest = branch.files.map(\.modified.timeIntervalSince1970).max() ?? 0
            return "\(branch.index.clipsByListedSidecar.count)|\(Int(newest))"
        }.joined(separator: ";")
    }

    /// Every sidecar the surveyed branches hold, keyed by the catalog path of
    /// the clip it speaks for. A branch that fails outright is skipped rather
    /// than failing the whole corpus.
    static func fetchSidecars(client: PCloudClient, branches: [Branch]) async -> [String: Sidecar] {
        var sidecars: [String: Sidecar] = [:]
        for branch in branches {
            let fetched: [String: Sidecar]
            do {
                fetched = try await fetchViaZip(client: client, branch: branch)
            } catch {
                // getzip has already failed against the real server once (it
                // takes a folderid, not a path) — never trust it as the only
                // road.
                fetched = await fetchSingly(client: client, branch: branch)
            }
            sidecars.merge(fetched) { _, new in new }
        }
        return sidecars
    }

    private static func fetchViaZip(client: PCloudClient, branch: Branch) async throws -> [String: Sidecar] {
        guard let folderID = try await client.folderSkeleton(path: branch.path, recursive: false).folderid else {
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
            guard let clip = branch.index.clip(forZipEntry: entry.name),
                  let sidecar = try? decoder.decode(Sidecar.self, from: entry.data) else { continue }
            sidecars[clip] = sidecar
        }
        return sidecars
    }

    /// The slow road: only the sidecars that speak for a clip, six at a time.
    private static func fetchSingly(client: PCloudClient, branch: Branch) async -> [String: Sidecar] {
        let wanted = branch.index.clipsByListedSidecar
        let files = branch.files.filter { wanted[$0.path] != nil }
        let decoder = JSONDecoder()
        var sidecars: [String: Sidecar] = [:]
        await withTaskGroup(of: (String, Data)?.self) { group in
            var iterator = files.makeIterator()
            var inFlight = 0
            func addNext(_ group: inout TaskGroup<(String, Data)?>) {
                guard let file = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard let url = try? await client.fileLink(fileID: file.fileID).url,
                          let tmp = try? await client.download(url) else { return nil }
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    guard let data = try? Data(contentsOf: tmp) else { return nil }
                    return (file.path, data)
                }
            }
            for _ in 0..<6 { addNext(&group) }
            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                if let (path, data) = result, let clip = wanted[path],
                   let sidecar = try? decoder.decode(Sidecar.self, from: data) {
                    sidecars[clip] = sidecar
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
