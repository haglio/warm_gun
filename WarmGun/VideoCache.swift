import Foundation
import WarmGunKit

/// In Application Support because iOS empties Caches under pressure.
actor VideoCache {
    private let directory: URL
    private var entries: [String: PrefetchPlanner.CachedFile] = [:]

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = directory
        try? dir.setResourceValues(values)
        entries = Self.loadIndex(at: directory)
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Clips", isDirectory: true)
    }

    func fileURL(for path: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: path))
    }

    func cachedPaths() -> Set<String> {
        Set(entries.keys)
    }

    func cachedFiles() -> [PrefetchPlanner.CachedFile] {
        Array(entries.values)
    }

    func store(temporary tmp: URL, for path: String) throws {
        let destination = fileURL(for: path)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        entries[path] = PrefetchPlanner.CachedFile(path: path, size: size, lastUsed: Date())
        saveIndex()
    }

    func markUsed(_ path: String) {
        guard let entry = entries[path] else { return }
        entries[path] = PrefetchPlanner.CachedFile(path: path, size: entry.size, lastUsed: Date())
    }

    func remove(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(at: fileURL(for: path))
            entries[path] = nil
        }
        if !paths.isEmpty { saveIndex() }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private struct Row: Codable {
        let path: String
        let size: Int64
        let lastUsed: Date
    }

    private func saveIndex() {
        let rows = entries.values.map { Row(path: $0.path, size: $0.size, lastUsed: $0.lastUsed) }
        if let data = try? JSONEncoder().encode(rows) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private static func loadIndex(at directory: URL) -> [String: PrefetchPlanner.CachedFile] {
        let url = directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }
        var entries: [String: PrefetchPlanner.CachedFile] = [:]
        for row in rows where FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName(for: row.path)).path) {
            entries[row.path] = PrefetchPlanner.CachedFile(path: row.path, size: row.size, lastUsed: row.lastUsed)
        }
        return entries
    }

    /// Swift's own hasher is randomized per launch, and AVFoundation sniffs the container by extension.
    static func fileName(for path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return String(hash, radix: 16) + (ext.isEmpty ? "" : "." + ext)
    }
}
