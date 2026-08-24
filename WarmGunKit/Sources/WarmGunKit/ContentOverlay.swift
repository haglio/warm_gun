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

    public let lanes: [Lane]

    public init(lanes: [Lane] = []) {
        self.lanes = lanes
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
