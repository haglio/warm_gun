import Foundation
import Testing
@testable import WarmGunKit

@Suite struct SidecarCorpusTests {
    @Test func theSavedCorpusKeepsEveryFieldASidecarCarriesForAReaderThatLearnsItLater() throws {
        let raw = Data(#"{"video": {"action": "site word", "labels": ["Alpha"], "later": {"x": 1}}}"#.utf8)
        let corpus = SidecarCorpus(records: ["1_sorted/a/portrait/one.mp4": raw])

        let saved = try JSONDecoder().decode(SidecarCorpus.self, from: JSONEncoder().encode(corpus))

        #expect(saved.records == corpus.records)
        #expect(saved.sidecars["1_sorted/a/portrait/one.mp4"]?.labels == ["Alpha"])
    }

    @Test func aCorpusSavedAsDecodedSidecarsReadsAsNoneSoTheMirrorIsFetchedAgain() {
        let old = Data(#"{"1_sorted/a/portrait/one.mp4": {"video": {"action": "site word"}, "favorite": false}}"#.utf8)
        #expect((try? JSONDecoder().decode(SidecarCorpus.self, from: old)) == nil)
    }
}
