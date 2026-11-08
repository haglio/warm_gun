import Foundation
import WarmGunKit
import os

enum MetadataFetcher {
    /// Read with `log show --predicate 'subsystem == "com.cmloegcmluin.warmgun"'`: the unified log
    /// keeps notices, never info lines, once the process is gone.
    static let log = Logger(subsystem: "com.cmloegcmluin.warmgun", category: "metadata")

    static func survey(client: PCloudClient, libraryPath: String, genauFlicksFolder: String?,
                       videoPaths: [String]) async -> [SurveyedBranch] {
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
        return branches
    }

    static func fetch(client: PCloudClient, files: [LibraryFile]) async -> [String: Data] {
        var records: [String: Data] = [:]
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
                if let (path, data) = result { records[path] = data }
                addNext(&group)
            }
        }
        return records
    }
}
