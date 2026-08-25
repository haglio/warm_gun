import Foundation

/// What the repo cannot say, said by a git-ignored file instead: the non-AI
/// buckets' folder names are library content, so which bucket is which TYPE —
/// and which folder forces an orientation — ships as data beside the app
/// (`content.local.json`, with a committed example documenting the shape),
/// never as source. Without an overlay every non-AI scene is simply a
/// full-length landscape scene.
public struct ContentOverlay: Codable, Equatable, Sendable {
    public struct Lane: Codable, Equatable, Sendable {
        /// Library-relative path prefix, e.g. `non_AI/<bucket>/<folder>`.
        public let prefix: String
        public let type: ClipType
        /// Set when the folder dictates one (a portrait-cuts folder); nil
        /// leaves the clip's own pixels in charge.
        public let orientation: Orientation?
        /// The checkbox title for an `.acts` lane — the word itself is library
        /// vocabulary, so it lives here, not in source.
        public let label: String?

        public init(prefix: String, type: ClipType, orientation: Orientation?, label: String?) {
            self.prefix = prefix
            self.type = type
            self.orientation = orientation
            self.label = label
        }
    }

    /// One of the combinable act buttons: a two-letter label, the queries that
    /// claim a clip's recorded act for it (first filter to match wins), and
    /// whether it is the catch-all that takes everything unclaimed — clips
    /// with no recorded act included.
    public struct ActFilter: Codable, Equatable, Sendable {
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
    public let actFilters: [ActFilter]
    /// Which recorded acts count as the acts type, for the AI clips whose act
    /// lives in the sidecar rather than in a folder. Matched the desktop's
    /// way: a normalized query as a contiguous substring of the normalized
    /// act. The words are library vocabulary and live only in the overlay.
    public let actQueries: [String]

    public init(lanes: [Lane] = [], actFilters: [ActFilter] = [], actQueries: [String] = []) {
        self.lanes = lanes
        self.actFilters = actFilters
        self.actQueries = actQueries
    }

    private enum CodingKeys: String, CodingKey {
        case lanes
        case actFilters = "act_filters"
        case actQueries = "act_queries"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lanes = try c.decodeIfPresent([Lane].self, forKey: .lanes) ?? []
        actFilters = try c.decodeIfPresent([ActFilter].self, forKey: .actFilters) ?? []
        actQueries = try c.decodeIfPresent([String].self, forKey: .actQueries) ?? []
    }

    /// The button that claims *act*: the first whose query matches, else the
    /// catch-all. Nil when no filters are defined at all (the feature is off),
    /// or when nothing claims the act and no catch-all exists.
    public func actBucket(for act: String?) -> String? {
        guard !actFilters.isEmpty else { return nil }
        let normalized = GroupIndex.normText(act)
        if !normalized.isEmpty {
            for filter in actFilters where !filter.isOther {
                if filter.queries.contains(where: { normalized.contains(GroupIndex.normText($0)) }) {
                    return filter.label
                }
            }
        }
        return actFilters.first(where: \.isOther)?.label
    }

    public func matchesActQuery(_ act: String) -> Bool {
        let normalized = GroupIndex.normText(act)
        guard !normalized.isEmpty else { return false }
        return actQueries.contains { normalized.contains(GroupIndex.normText($0)) }
    }

    public static let empty = ContentOverlay()

    /// The most specific lane covering *path* — longest prefix wins.
    public func lane(for path: String) -> Lane? {
        lanes.filter { path.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
    }

    /// What the acts checkbox is called, when any lane defines acts at all.
    public var actsLabel: String? {
        lanes.first { $0.type == .acts }?.label
    }
}
