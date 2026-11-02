import Foundation

/// What the repo cannot say, said by a git-ignored file instead: the non-AI
/// buckets' folder names are library content, so which bucket is which TYPE —
/// and which folder forces an shape — ships as data beside the app
/// (`content.local.json`, with a committed example documenting the shape),
/// never as source. Without an overlay every non-AI scene is simply a
/// full-length landscape scene.
///
/// The lanes are a *fallback*: the desktop records every video's type on its
/// sidecar, and a lane answers only for a video whose sidecar the phone has not
/// read.
public struct ContentOverlay: Codable, Equatable, Sendable {
    public struct Lane: Codable, Equatable, Sendable {
        /// Library-relative path prefix, e.g. `non_AI/<bucket>/<folder>`.
        public let prefix: String
        public let type: VideoType
        /// Set when the folder dictates one (a portrait-cuts folder); nil
        /// leaves the video's own pixels in charge.
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

    /// One of the combinable action buttons: a two-letter label, the queries that
    /// claim a video's recorded action for it (first filter to match wins), and
    /// whether it is the catch-all that takes everything unclaimed — videos
    /// with no recorded action included.
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

    /// The button that claims *action*: the first whose query matches, else the
    /// catch-all. Nil when no filters are defined at all (the feature is off),
    /// or when nothing claims the action and no catch-all exists.
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

    /// The most specific lane covering *path* — longest prefix wins.
    public func lane(for path: String) -> Lane? {
        lanes.filter { path.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
    }
}
