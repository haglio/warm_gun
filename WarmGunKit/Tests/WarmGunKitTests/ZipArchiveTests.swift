import Foundation
import Testing
@testable import WarmGunKit

/// A two-entry zip built with Python's zipfile: `plain.json` stored, and
/// `nested/deflated.json` deflated (repetitive enough to actually compress).
@Suite struct ZipArchiveTests {
    static let fixture = Data(base64Encoded:
        "UEsDBBQAAAAAAAAAIQCvrBtWBwAAAAcAAAAKAAAAcGxhaW4uanNvbnsiYSI6MX1QSwMEFAAAAAgACboYXfoeQUw6AAAAqAAAABQAAABuZXN0ZWQvZGVmbGF0ZWQuanNvbqtWKstMSc1XsqpWSkwuyczPU7JSSswpyEhU0lEqKMrPLSgBChQAOcWpqSlApqGRsYmpUm1tNZ31AQBQSwECFAMUAAAAAAAAACEAr6wbVgcAAAAHAAAACgAAAAAAAAAAAAAAgAEAAAAAcGxhaW4uanNvblBLAQIUAxQAAAAIAAm6GF36HkFMOgAAAKgAAAAUAAAAAAAAAAAAAACAAS8AAABuZXN0ZWQvZGVmbGF0ZWQuanNvblBLBQYAAAAAAgACAHoAAACbAAAAAAA=")!

    /// A toy inflater for the test: the deflated entry's plaintext is known,
    /// so the "inflater" just checks it was handed compressed bytes of the
    /// right advertised sizes and returns the known plaintext. The real one
    /// (Apple's Compression framework) lives in the app target — the Kit
    /// stays pure Foundation by taking inflation as a function.
    static let knownPlain = Data(String(repeating: #"{"video":{"action":"alpha","prompt":"p","seed":"12345"}}"#, count: 3).utf8)

    @Test func readsStoredAndDeflatedEntriesThroughTheInjectedInflater() throws {
        var inflaterCalls = 0
        let entries = try ZipArchive.entries(in: Self.fixture) { compressed, uncompressedSize in
            inflaterCalls += 1
            #expect(uncompressedSize == Self.knownPlain.count)
            #expect(compressed.count < Self.knownPlain.count)
            return Self.knownPlain
        }
        #expect(entries.count == 2)
        #expect(entries[0].name == "plain.json")
        #expect(entries[0].data == Data(#"{"a":1}"#.utf8))
        #expect(entries[1].name == "nested/deflated.json")
        #expect(entries[1].data == Self.knownPlain)
        #expect(inflaterCalls == 1)  // the stored entry never needs it
    }

    @Test func refusesABodyThatIsNotAZip() {
        #expect(throws: ZipArchive.Failure.self) {
            // What a pCloud error envelope would look like if it ever came back
            // where a zip was expected.
            try ZipArchive.entries(in: Data(#"{"result": 2000, "error": "Log in failed."}"#.utf8)) { _, _ in nil }
        }
    }
}
