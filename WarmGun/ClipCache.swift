import Foundation
import WarmGunKit

/// The on-device copy of every clip Warm Gun has fetched, keyed by library path.
///
/// Lives in Application Support (not Caches, which iOS may purge under
/// pressure — a purge would silently undo "download everything"), excluded
/// from backups because the library is the backup. The index is held in memory
/// and written beside the files, so a relaunch knows what it has without
/// stat-ing a few thousand files.
actor ClipCache {
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

    func isCached(_ path: String) -> Bool {
        entries[path] != nil
    }

    func cachedPaths() -> Set<String> {
        Set(entries.keys)
    }

    func totalBytes() -> Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    func cachedFiles() -> [PrefetchPlanner.CachedFile] {
        Array(entries.values)
    }

    /// Moves a finished download into place. Never copies a partial file: the
    /// temp file is the downloader's, complete by construction.
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

    func removeAll() {
        remove(Array(entries.keys))
    }

    // MARK: - index

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

    /// Trusts the index only for files that are actually present — a file the
    /// system removed without our knowing must not be promised to the player.
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

    /// A stable on-disk name for a library path: FNV-1a over the path (Swift's
    /// own hasher is randomized per launch) plus the real extension so
    /// AVFoundation sniffs the container the way it would on the desktop.
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
