import Foundation

/// One thing that happened to one clip. The phone keeps its own stores because
/// the desktop's `favs.csv` and `watch_stats.json` live outside pCloud and prune
/// paths that are not on the writing machine; this is the record that lets a
/// later, desktop-side step fold a trip's worth of taps back into them.
public struct JournalEvent: Codable, Equatable, Sendable {
    /// Unix seconds — the merge is chronological, and a phone away from home has
    /// no other clock the desktop trusts.
    public let t: Int
    /// `favorite`, `unfavorite`, `weird`, `lock`, `completion` or `skip`.
    public let event: String
    /// The library-relative path of the *original*, which is how Warm Gun names a
    /// clip everywhere.
    public let path: String

    public init(t: Int, event: String, path: String) {
        self.t = t
        self.event = event
        self.path = path
    }
}

/// The `warm-gun-journal.jsonl` format: one JSON object per line, appended.
public enum Journal {
    /// The key order is spelled out by hand rather than left to `JSONEncoder`,
    /// which sorts or reorders depending on the Foundation underneath: this file
    /// is read by people as well as parsers, and `t` first keeps it scannable.
    public static func line(_ event: JournalEvent) -> String {
        "{\"t\":\(event.t),\"event\":\(quoted(event.event)),\"path\":\(quoted(event.path))}"
    }

    /// A JSON string literal, with everything JSON insists on escaping escaped.
    private static func quoted(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            // A reader that splits on `Character.isNewline` cuts a line at any
            // scalar in that alphabet, so every one leaves here escaped — NEL
            // and the two Unicode separators included, not just the controls.
            case let c where c.value < 0x20 || c.value == 0x85 || c.value == 0x2028 || c.value == 0x2029:
                out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(character)
            }
        }
        return out + "\""
    }
}
