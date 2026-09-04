import Foundation

/// The clips held onto, each under the key its lane is filed by
/// (`LibraryPaths.favoriteKey`): a generated clip's stem, which is the one name
/// the desktop's `favs.csv` and this store can both say, and the whole path for
/// a genau loop or a real scene, where nothing promises two files do not share
/// a name. Every lane can be held, which is what lets the flag the desktop
/// stamps on their sidecars land here.
public struct Favorites: Codable, Equatable, Sendable {
    /// Persisted under its old name, so an app update costs no favorites.
    public var held: Set<String>
    /// Stems this phone has let go of, held until the desktop's own record
    /// agrees. The desktop's record — the flag on the sidecars, or a dropped
    /// `favs.csv` — is a snapshot from the last time its stage ran, and it is
    /// read again on every launch, so without this an unfavorite made away from
    /// home is undone by the next one: the weird gesture's two-step demotion
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
        guard let key = LibraryPaths.favoriteKey(forClip: path) else { return false }
        return held.contains(key)
    }

    /// True when this tap actually added something, which is what the journal
    /// records: locking an already-favorited clip is not a second favorite.
    public mutating func insert(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forClip: path) else { return false }
        // Holding it again settles the question: a refusal made before says
        // nothing about the choice just made.
        released.remove(key)
        return held.insert(key).inserted
    }

    /// True when the clip really was a favorite until now — what the weird
    /// gesture's first step reads to know whether it demoted or dropped.
    public mutating func remove(path: String) -> Bool {
        guard let key = LibraryPaths.favoriteKey(forClip: path) else { return false }
        released.insert(key)
        return held.remove(key) != nil
    }

    /// Fold in the desktop's record — the flag Evolver stamps on the sidecars,
    /// or a `favs.csv` carried over from the PC. It only ever adds, minus what
    /// this phone has let go of: the record is a snapshot from before the trip,
    /// so taking it as the whole truth would undo every favorite made since,
    /// and taking it blindly would undo every unfavorite.
    /// *covering* is what the record could have spoken for at all — the corpus
    /// this run actually fetched. A refusal is dropped only inside it: absence
    /// from a record that never reached a lane says the lane was missing, not
    /// that the desktop agreed, and reading it as agreement would hand the
    /// favorite straight back. A record that is complete by construction — a
    /// `favs.csv` — passes none, and every refusal is then in scope.
    public mutating func adopt(flagged: Set<String>, covering scope: Set<String>? = nil) {
        held.formUnion(flagged.subtracting(released))
        // A refusal the desktop has caught up with has done its work: its key
        // is no longer claimed, so there is nothing left to refuse.
        released.subtract((scope ?? released).subtracting(flagged))
    }
}

/// The desktop's favorites file, as Excel wants it: a `local_file,web_url`
/// header and then CRLF rows of two quoted cells, each an `=HYPERLINK` formula
/// with its inner quotes doubled. Warm Gun only ever reads one — dropped into the
/// pCloud folder it syncs through — and only for the stems.
public enum FavsCSV {
    /// Every generated clip the file names. The formula's *second* argument is
    /// the one read, exactly as `random_favs_browser.py` reads it: it is the
    /// plain Windows path, where the first is a percent-encoded `file://` URI.
    ///
    /// Only the AI lane can be read from here. The file names whichever video
    /// Fun Time plays, and for the other two lanes that is the video itself —
    /// but those are filed under their library-relative path, which a Windows
    /// absolute path cannot be turned into without knowing where the library
    /// root sits on that machine. They arrive by the other road instead: the
    /// flag Evolver stamps on their sidecars, which is keyed by the clip.
    public static func keys(in text: String) -> Set<String> {
        var keys: Set<String> = []
        // A byte-order mark is part of the first line, not of the first cell, so
        // it would otherwise cost whichever row leads the file.
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : text[...]
        for line in body.split(whereSeparator: \.isNewline) {
            guard let cell = firstCell(of: line).map({ $0.trimmingCharacters(in: .whitespaces) }),
                  let display = hyperlinkDisplay(cell),
                  let stem = LibraryPaths.stem(ofUpscaleReference: display) else { continue }
            keys.insert(stem)
        }
        return keys
    }

    private static let formulaPrefix = "=HYPERLINK(\""
    private static let formulaSeparator = "\";\""
    private static let formulaSuffix = "\")"

    /// The `local_file` column, un-doubling the quotes Excel doubled.
    private static func firstCell(of line: Substring) -> String? {
        guard line.first == "\"" else {
            // Keep empty subsequences: an empty local_file cell must yield an
            // empty cell, never slide the parser onto the web_url column.
            return line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)
        }
        var cell = ""
        var i = line.index(after: line.startIndex)
        while i < line.endIndex {
            let character = line[i]
            i = line.index(after: i)
            guard character == "\"" else {
                cell.append(character)
                continue
            }
            guard i < line.endIndex, line[i] == "\"" else { return cell }
            cell.append("\"")
            i = line.index(after: i)
        }
        return nil  // a row cut off mid-cell names nothing
    }

    private static func hyperlinkDisplay(_ cell: String) -> String? {
        guard cell.hasPrefix(formulaPrefix), cell.hasSuffix(formulaSuffix) else { return nil }
        let inner = cell.dropFirst(formulaPrefix.count).dropLast(formulaSuffix.count)
        guard let separator = inner.range(of: formulaSeparator) else { return nil }
        return String(inner[separator.upperBound...])
    }
}
