import Foundation

public struct ContentOverlay: Codable, Equatable, Sendable {
    public struct Lane: Codable, Equatable, Sendable {
        public let prefix: String
        public let type: VideoType
        public let shape: VideoShape?

        private enum CodingKeys: String, CodingKey {
            case prefix, type
            case shape = "orientation"
        }

        public init(prefix: String, type: VideoType, shape: VideoShape?) {
            self.prefix = prefix
            self.type = type
            self.shape = shape
        }
    }

    public struct ActionFilter: Codable, Equatable, Sendable {
        public let label: String
        public let queries: [String]
        public let isOther: Bool

        public init(label: String, queries: [String], isOther: Bool) {
            self.label = label
            self.queries = queries
            self.isOther = isOther
        }

        private enum CodingKeys: String, CodingKey {
            case label, queries
            case isOther = "is_other"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            queries = try c.decodeIfPresent([String].self, forKey: .queries) ?? []
            isOther = try c.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
        }
    }

    public let lanes: [Lane]
    public let actionFilters: [ActionFilter]
    public init(lanes: [Lane] = [], actionFilters: [ActionFilter] = []) {
        self.lanes = lanes
        self.actionFilters = actionFilters
    }

    private enum CodingKeys: String, CodingKey {
        case lanes
        case actionFilters = "act_filters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lanes = try c.decodeIfPresent([Lane].self, forKey: .lanes) ?? []
        actionFilters = try c.decodeIfPresent([ActionFilter].self, forKey: .actionFilters) ?? []
    }

    public func actionBucket(for action: String?) -> String? {
        guard !actionFilters.isEmpty else { return nil }
        let normalized = GroupIndex.normText(action)
        if !normalized.isEmpty {
            for filter in actionFilters where !filter.isOther {
                if filter.queries.contains(where: { normalized.contains(GroupIndex.normText($0)) }) {
                    return filter.label
                }
            }
        }
        return actionFilters.first(where: \.isOther)?.label
    }

    public static let empty = ContentOverlay()

    public func lane(for path: String) -> Lane? {
        lanes.filter { path.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
    }
}
