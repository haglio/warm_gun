import Foundation

/// The videos held onto, each under the key its lane is filed by
/// (`LibraryPaths.favoriteKey`): a generated video's stem, which its original
/// and its upscale share, and the whole path for a Genau flick or a real scene,
/// where nothing promises two files do not share a name. Every lane can be held, which is what lets the flag the desktop
/// stamps on their sidecars land here.
public struct Favorites: Codable, Equatable, Sendable {
    /// Persisted under its old name, so an app update costs no favorites.
    public var held: Set<String>
    /// Stems this phone has let go of, held until the desktop's own record
    /// agrees. The desktop's record — the flag on the sidecars — is a snapshot from the last time its stage ran, and it is
    /// read again on every launch, so without this an unfavorite made away from
    /// home is undone by the next one: the trash gesture's two-step demotion
    /// would take its first step forever and never reach the second.
    public private(set) var released: Set<String>

    public init(held: Set<String> = [], released: Set<String> = []) {
        self.held = held
        self.released = released
    }

    private enum CodingKeys: String, CodingKey {
        case held = "stems"
        case released
    }

    /// A blob written before the refusals existed decodes with none — an app
    /// update must never cost the favorites themselves.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        held = try c.decode(Set<String>.self, forKey: .held)
        released = try c.decodeIfPresent(Set<String>.self, forKey: .released) ?? []
    }

    public func contains(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        return held.contains(key)
    }

    /// True when this tap actually added something, which is what the journal
    /// records: locking an already-favorited video is not a second favorite.
    public mutating func insert(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        // Holding it again settles the question: a refusal made before says
        // nothing about the choice just made.
        released.remove(key)
        return held.insert(key).inserted
    }

    /// True when the video really was a favorite until now — what the trash
    /// gesture's first step reads to know whether it demoted or dropped.
    public mutating func remove(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forVideo: path) else { return false }
        released.insert(key)
        return held.remove(key) != nil
    }

    /// Keys named the way Genau's flicks folder named a flick before it split
    /// into 2D and VR, carried to where the video is now
    /// (`LibraryPaths.rekeyedFlatGenau`), so the split costs no favorites.
    public mutating func rekeyFlatGenau(against current: Set<String>) {
        held = LibraryPaths.rekeyedFlatGenau(held, against: current)
        released = LibraryPaths.rekeyedFlatGenau(released, against: current)
    }

    /// Fold in the desktop's record — the flag Evolver stamps on the sidecars.
    /// It only ever adds, minus what
    /// this phone has let go of: the record is a snapshot from before the trip,
    /// so taking it as the whole truth would undo every favorite made since,
    /// and taking it blindly would undo every unfavorite.
    /// *covering* is what the record could have spoken for at all — the corpus
    /// this run actually fetched. A refusal is dropped only inside it: absence
    /// from a record that never reached a lane says the lane was missing, not
    /// that the desktop agreed, and reading it as agreement would hand the
    /// favorite straight back.
    public mutating func adopt(flagged: Set<String>, covering scope: Set<String>) {
        held.formUnion(flagged.subtracting(released))
        // A refusal the desktop has caught up with has done its work: its key
        // is no longer claimed, so there is nothing left to refuse.
        released.subtract(scope.subtracting(flagged))
    }
}
