import Foundation

public struct Favorites: Codable, Equatable, Sendable {
    public var held: Set<String>
    public private(set) var released: Set<String>

    public init(held: Set<String> = [], released: Set<String> = []) {
        self.held = held
        self.released = released
    }

    private enum CodingKeys: String, CodingKey {
        case held = "stems"
        case released
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        held = try c.decode(Set<String>.self, forKey: .held)
        released = try c.decodeIfPresent(Set<String>.self, forKey: .released) ?? []
    }

    public func contains(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        return held.contains(key)
    }

    public mutating func insert(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        released.remove(key)
        return held.insert(key).inserted
    }

    public mutating func remove(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        released.insert(key)
        return held.remove(key) != nil
    }

    public mutating func rekeyFlatGenau(against current: Set<String>) {
        held = LibraryPaths.rekeyedFlatGenau(held, against: current)
        released = LibraryPaths.rekeyedFlatGenau(released, against: current)
    }

    public mutating func adopt(flagged: Set<String>, covering scope: Set<String>) {
        held.formUnion(flagged.subtracting(released))
        released.subtract(scope.subtracting(flagged))
    }
}
