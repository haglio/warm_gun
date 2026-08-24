import Testing
@testable import WarmGunKit

@Suite struct JournalTests {
    @Test func writesOneCompactObjectPerEventWithItsKeysInTheDocumentedOrder() {
        // The desktop merges this file by eye as much as by parser, so the shape
        // is fixed: t, then event, then path, and nothing else on the line.
        let line = Journal.line(JournalEvent(t: 1_700_000_000, event: "favorite",
                                             path: "1_sorted/alpha/portrait/clip-one.mp4"))
        #expect(line == #"{"t":1700000000,"event":"favorite","path":"1_sorted/alpha/portrait/clip-one.mp4"}"#)
    }
}

extension JournalTests {
    @Test func escapesWhatJSONCannotCarryRawSoOneOddStemCannotTearTheLine() {
        let awkward = JournalEvent(t: 1, event: "skip",
                                   path: #"1_sorted/alpha/portrait/clip "one"\two.mp4"#)
        #expect(Journal.line(awkward)
                == #"{"t":1,"event":"skip","path":"1_sorted/alpha/portrait/clip \"one\"\\two.mp4"}"#)
        #expect(Journal.events(in: Journal.line(awkward)) == [awkward])

        // A control character would end the line early and take the rest of the
        // file's parse with it, so every one of them is spelled out.
        let torn = JournalEvent(t: 2, event: "weird", path: "clip\ttwo\nthree\u{01}")
        let line = Journal.line(torn)
        #expect(!line.unicodeScalars.contains { $0.value < 0x20 })
        #expect(Journal.events(in: line) == [torn])
    }
}

extension JournalTests {
    @Test func skipsTheBlankAndHalfWrittenLinesAnAppendedFileCollects() {
        // A journal is appended to on a phone that can be killed mid-write, and
        // one torn line must not cost the trip's other events.
        let good = JournalEvent(t: 1_700_000_000, event: "completion",
                                path: "1_sorted/alpha/portrait/clip-one.mp4")
        let text = """

        \(Journal.line(good))
        {"t":1700000001,"event":"skip","pa

        not json at all
        """
        #expect(Journal.events(in: text) == [good])
        #expect(Journal.events(in: "").isEmpty)
    }
}

extension JournalTests {
    @Test func readsBackEveryEventItWrote() {
        let events = [JournalEvent(t: 1_700_000_000, event: "lock",
                                   path: "1_sorted/alpha/portrait/clip-one.mp4"),
                      JournalEvent(t: 1_700_000_042, event: "weird",
                                   path: "1_sorted/beta/landscape/clip-two.mp4")]
        let text = events.map(Journal.line).joined(separator: "\n")
        #expect(Journal.events(in: text) == events)
    }
}

extension JournalTests {
    @Test func aPathCarryingAnExoticLineBreakStillRoundTrips() {
        // `events(in:)` splits on `Character.isNewline`, whose alphabet is wider
        // than \n and \r: NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR would cut
        // a line in two and silently lose the event unless the writer escapes
        // them too.
        for scalar in ["\u{85}", "\u{2028}", "\u{2029}"] {
            let event = JournalEvent(t: 7, event: "skip", path: "1_sorted/alpha/portrait/a\(scalar)b.mp4")
            #expect(Journal.events(in: Journal.line(event)) == [event])
        }
    }
}
