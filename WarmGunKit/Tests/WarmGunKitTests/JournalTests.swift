import Foundation
import Testing
@testable import WarmGunKit

@Suite struct JournalTests {
    @Test func writesOneCompactObjectPerEventWithItsKeysInTheDocumentedOrder() {
        let line = Journal.line(JournalEvent(t: 1_700_000_000, event: "favorite",
                                             path: "1_sorted/alpha/portrait/video-one.mp4"))
        #expect(line == #"{"t":1700000000,"event":"favorite","path":"1_sorted/alpha/portrait/video-one.mp4"}"#)
    }

    static func read(_ line: String) -> JournalEvent? {
        try? JSONDecoder().decode(JournalEvent.self, from: Data(line.utf8))
    }
}

extension JournalTests {
    @Test func escapesWhatJSONCannotCarryRawSoOneOddStemCannotTearTheLine() {
        let awkward = JournalEvent(t: 1, event: "skip",
                                   path: #"1_sorted/alpha/portrait/video "one"\two.mp4"#)
        #expect(Journal.line(awkward)
                == #"{"t":1,"event":"skip","path":"1_sorted/alpha/portrait/video \"one\"\\two.mp4"}"#)
        #expect(Self.read(Journal.line(awkward)) == awkward)

        let torn = JournalEvent(t: 2, event: "trash", path: "video\ttwo\nthree\u{01}")
        let line = Journal.line(torn)
        #expect(!line.unicodeScalars.contains { $0.value < 0x20 })
        #expect(Self.read(line) == torn)
    }
}

extension JournalTests {
    @Test func aPathCarryingAnExoticLineBreakStaysOnItsOneLine() {
        for scalar in ["\u{85}", "\u{2028}", "\u{2029}"] {
            let event = JournalEvent(t: 7, event: "skip", path: "1_sorted/alpha/portrait/a\(scalar)b.mp4")
            let line = Journal.line(event)
            let breaksALine = line.contains(where: \.isNewline)
            #expect(!breaksALine)
            #expect(Self.read(line) == event)
        }
    }
}
