import Foundation

/// The clips held onto, kept by stem rather than by path.
///
/// A stem is unique library-wide and is the one name both renditions share, so
/// it is also the only thing the desktop's `favs.csv` — which lists Windows
/// paths to upscales — and Warm Gun's own store can agree on. Every lane has
/// one: a genau loop and a real scene are held exactly as a generated clip is,
/// which is what lets the flag the desktop stamps on their sidecars land here.
public struct Favorites: Codable, Equatable, Sendable {
    public var stems: Set<String>

    public init(stems: Set<String> = []) {
        self.stems = stems
    }

    public func contains(path: String) -> Bool {
        guard let stem = LibraryPaths.stem(ofClip: path) else { return false }
        return stems.contains(stem)
    }

    /// True when this tap actually added something, which is what the journal
    /// records: locking an already-favorited clip is not a second favorite.
    public mutating func insert(path: String) -> Bool {
        guard let stem = LibraryPaths.stem(ofClip: path) else { return false }
        return stems.insert(stem).inserted
    }

    /// True when the clip really was a favorite until now — what the weird
    /// gesture's first step reads to know whether it demoted or dropped.
    public mutating func remove(path: String) -> Bool {
        guard let stem = LibraryPaths.stem(ofClip: path) else { return false }
        return stems.remove(stem) != nil
    }

    /// Fold in an import — a `favs.csv` carried over from the PC. It only ever
    /// adds: the desktop's file is a snapshot from before the trip, so treating
    /// it as the whole truth would undo every favorite made since.
    public mutating func merge(stems: Set<String>) {
        self.stems.formUnion(stems)
    }
}

/// The desktop's favorites file, as Excel wants it: a `local_file,web_url`
/// header and then CRLF rows of two quoted cells, each an `=HYPERLINK` formula
/// with its inner quotes doubled. Warm Gun only ever reads one — dropped into the
/// pCloud folder it syncs through — and only for the stems.
public enum FavsCSV {
    /// Every clip the file names. The formula's *second* argument is the one
    /// read, exactly as `random_favs_browser.py` reads it: it is the plain
    /// Windows path, where the first is a percent-encoded `file://` URI.
    public static func stems(in text: String) -> Set<String> {
        var stems: Set<String> = []
        // A byte-order mark is part of the first line, not of the first cell, so
        // it would otherwise cost whichever row leads the file.
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : text[...]
        for line in body.split(whereSeparator: \.isNewline) {
            guard let cell = firstCell(of: line).map({ $0.trimmingCharacters(in: .whitespaces) }),
                  let display = hyperlinkDisplay(cell),
                  let stem = LibraryPaths.stem(ofUpscaleReference: display) else { continue }
            stems.insert(stem)
        }
        return stems
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
