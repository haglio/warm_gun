import Compression
import Foundation
import WarmGunKit
import os

enum MetadataFetcher {
    /// Read with `log show --predicate 'subsystem == "com.cmloegcmluin.warmgun"'`: the unified log
    /// keeps notices, never info lines, once the process is gone.
    static let log = Logger(subsystem: "com.cmloegcmluin.warmgun", category: "metadata")

    static func survey(client: PCloudClient, libraryPath: String, genauFlicksFolder: String?,
                       videoPaths: [String]) async -> MirrorSurvey {
        var branches: [SurveyedBranch] = []
        for branch in LibraryPaths.MetadataBranch.allCases {
            guard let path = branch.path(forLibrary: libraryPath, genauFlicksFolder: genauFlicksFolder) else {
                log.notice("\(String(describing: branch)) branch: no path for this library")
                continue
            }
            let files: [LibraryFile]
            do {
                files = try await client.listLibrary(path: path)
            } catch {
                log.error("\(String(describing: branch)) branch would not list: \(error.localizedDescription)")
                continue
            }
            let index = SidecarIndex(branch: branch, videoPaths: videoPaths,
                                     listing: files.map(\.path))
            log.notice("\(String(describing: branch)) branch: \(files.count) files listed, \(index.videosByListedSidecar.count) speak for a video")
            guard !index.videosByListedSidecar.isEmpty else { continue }
            branches.append(SurveyedBranch(path: path, files: files, index: index))
        }
        return MirrorSurvey(branches: branches)
    }

    static func fetchSidecars(client: PCloudClient, branches: [SurveyedBranch]) async -> [String: Data] {
        var sidecars: [String: Data] = [:]
        for branch in branches {
            let fetched: [String: Data]
            do {
                fetched = try await fetchViaZip(client: client, branch: branch)
                log.notice("\(branch.path, privacy: .private): \(fetched.count) sidecars by zip")
            } catch {
                log.error("\(branch.path, privacy: .private): zip failed (\(error.localizedDescription)), fetching singly")
                fetched = await fetchSingly(client: client, branch: branch)
                log.notice("\(branch.path, privacy: .private): \(fetched.count) of \(branch.index.videosByListedSidecar.count) sidecars singly")
            }
            sidecars.merge(fetched) { _, new in new }
        }
        return sidecars
    }

    private static func fetchViaZip(client: PCloudClient, branch: SurveyedBranch) async throws -> [String: Data] {
        guard let folderID = try await client.folderSkeleton(path: branch.path, recursive: false).folderid else {
            throw ZipArchive.Failure(reason: "metadata folder has no id")
        }
        let body = try await client.downloadRaw(PCloudAPI.getZip(folderID: folderID, auth: ""), patientFirstByte: true)
        if body.first == UInt8(ascii: "{") {
            // pCloud answers errors as JSON even where a zip was asked for.
            _ = try PCloudAPI.decode(EmptyPayload.self, from: body)
        }
        var sidecars: [String: Data] = [:]
        for entry in try ZipArchive.entries(in: body, inflate: inflate) {
            guard let video = branch.index.video(forZipEntry: entry.name) else { continue }
            sidecars[video] = entry.data
        }
        return sidecars
    }

    private static func fetchSingly(client: PCloudClient, branch: SurveyedBranch) async -> [String: Data] {
        let wanted = branch.index.videosByListedSidecar
        let files = branch.files.filter { wanted[$0.path] != nil }
        var sidecars: [String: Data] = [:]
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
                if let (path, data) = result, let video = wanted[path] {
                    sidecars[video] = data
                }
                addNext(&group)
            }
        }
        return sidecars
    }

    struct EmptyPayload: Decodable {}

    /// Apple's ZLIB variant is the headerless RFC 1951 stream that zip entries carry (method 8).
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
