import Foundation

public struct SidecarCorpus: Codable, Equatable, Sendable {
    public private(set) var records: [String: Data]

    public init(records: [String: Data] = [:]) {
        self.records = records
    }

    public var sidecars: [String: Sidecar] {
        let decoder = JSONDecoder()
        return records.compactMapValues { try? decoder.decode(Sidecar.self, from: $0) }
    }
}
