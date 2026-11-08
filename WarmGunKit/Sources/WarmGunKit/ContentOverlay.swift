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

    public let lanes: [Lane]
    public init(lanes: [Lane] = []) {
        self.lanes = lanes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lanes = try c.decodeIfPresent([Lane].self, forKey: .lanes) ?? []
    }

    public static let empty = ContentOverlay()

    public func lane(for path: String) -> Lane? {
        lanes.filter { path.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
    }
}
