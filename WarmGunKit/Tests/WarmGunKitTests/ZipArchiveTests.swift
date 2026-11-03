import Foundation
import Testing
@testable import WarmGunKit

/// Built with Python's zipfile: `plain.json` stored, `nested/deflated.json` deflated.
@Suite struct ZipArchiveTests {
    static let fixture = Data(base64Encoded:
        "UEsDBBQAAAAAAAAAIQCvrBtWBwAAAAcAAAAKAAAAcGxhaW4uanNvbnsiYSI6MX1QSwMEFAAAAAgACboYXfoeQUw6AAAAqAAAABQAAABuZXN0ZWQvZGVmbGF0ZWQuanNvbqtWKstMSc1XsqpWSkwuyczPU7JSSswpyEhU0lEqKMrPLSgBChQAOcWpqSlApqGRsYmpUm1tNZ31AQBQSwECFAMUAAAAAAAAACEAr6wbVgcAAAAHAAAACgAAAAAAAAAAAAAAgAEAAAAAcGxhaW4uanNvblBLAQIUAxQAAAAIAAm6GF36HkFMOgAAAKgAAAAUAAAAAAAAAAAAAACAAS8AAABuZXN0ZWQvZGVmbGF0ZWQuanNvblBLBQYAAAAAAgACAHoAAACbAAAAAAA=")!

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
        #expect(inflaterCalls == 1)
    }

    @Test func refusesABodyThatIsNotAZip() {
        #expect(throws: ZipArchive.Failure.self) {
            try ZipArchive.entries(in: Data(#"{"result": 2000, "error": "Log in failed."}"#.utf8)) { _, _ in nil }
        }
    }
}

extension ZipArchiveTests {
    static let archiveWithAFolderRow = Data(base64Encoded:
        "UEsDBBQAAAAAAAAAIVwAAAAAAAAAAAAAAAAHAAAAZm9sZGVyL1BLAwQUAAAAAAAAACFcr6wbVgcAAAAHAAAAEQAAAGZvbGRlci9wbGFpbi5qc29ueyJhIjoxfVBLAQIUABQAAAAAAAAAIVwAAAAAAAAAAAAAAAAHAAAAAAAAAAAAAACAAQAAAABmb2xkZXIvUEsBAhQAFAAAAAAAAAAhXK+sG1YHAAAABwAAABEAAAAAAAAAAAAAAIABJQAAAGZvbGRlci9wbGFpbi5qc29uUEsFBgAAAAACAAIAdAAAAFsAAAAAAA==")!

    @Test func aFolderRowYieldsNoEntry() throws {
        let entries = try ZipArchive.entries(in: Self.archiveWithAFolderRow) { _, _ in nil }
        #expect(entries.map(\.name) == ["folder/plain.json"])
    }

    @Test func anArchiveCommentDoesNotHideTheDirectory() throws {
        var commented = Self.fixture
        commented[commented.count - 2] = 5
        commented.append(Data("hello".utf8))
        let entries = try ZipArchive.entries(in: commented) { _, _ in Self.knownPlain }
        #expect(entries.count == 2)
    }

    @Test func aSliceOfABodyReadsTheSameAsTheWholeOfIt() throws {
        let padded = Data([0, 0, 0]) + Self.fixture
        let entries = try ZipArchive.entries(in: padded[3...]) { _, _ in Self.knownPlain }
        #expect(entries.map(\.name) == ["plain.json", "nested/deflated.json"])
    }

    @Test func anInflaterThatGivesUpFailsTheWholeArchive() {
        #expect(throws: ZipArchive.Failure.self) {
            try ZipArchive.entries(in: Self.fixture) { _, _ in nil }
        }
    }

    @Test func anInflatedEntryOfTheWrongSizeFailsTheWholeArchive() {
        #expect(throws: ZipArchive.Failure.self) {
            try ZipArchive.entries(in: Self.fixture) { _, _ in Data("short".utf8) }
        }
    }
}
