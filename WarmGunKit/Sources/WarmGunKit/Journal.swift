import Foundation

public struct JournalEvent: Codable, Equatable, Sendable {
    public let t: Int
    public let event: String
    public let path: String

    public init(t: Int, event: String, path: String) {
        self.t = t
        self.event = event
        self.path = path
    }
}

public enum Journal {
    /// JSONEncoder's key order depends on the Foundation underneath, so the order is spelled out here.
    public static func line(_ event: JournalEvent) -> String {
        "{\"t\":\(event.t),\"event\":\(quoted(event.event)),\"path\":\(quoted(event.path))}"
    }

    private static func quoted(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20 || c.value == 0x85 || c.value == 0x2028 || c.value == 0x2029:
                out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(character)
            }
        }
        return out + "\""
    }
}
