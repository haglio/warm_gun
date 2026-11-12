import Foundation

public struct SidecarCorpus: Codable, Equatable, Sendable {
    public private(set) var records: [String: Data]
    private var written: [String: Date]

    public init() {
        records = [:]
        written = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case records, written
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decode([String: Data].self, forKey: .records)
        written = try c.decodeIfPresent([String: Date].self, forKey: .written) ?? [:]
    }

    public var sidecars: [String: Sidecar] {
        let decoder = JSONDecoder()
        return records.compactMapValues { try? decoder.decode(Sidecar.self, from: $0) }
    }

    public mutating func keep(_ record: Data, for video: String, written when: Date) {
        records[video] = record
        written[video] = when
    }

    public mutating func keepGallery(_ file: Data, read gallery: GalleryRecords, written when: Date) {
        for video in gallery.videosByKey.values {
            records[video] = nil
            written[video] = nil
        }
        for (video, record) in gallery.records(in: file) {
            keep(record, for: video, written: when)
        }
    }

    public func stale(in branch: SurveyedBranch) -> [LibraryFile] {
        branch.files.filter { file in
            guard let video = branch.index.videosByListedSidecar[file.path] else { return false }
            return written[video].map { file.modified > $0 } ?? true
        }
    }
}
