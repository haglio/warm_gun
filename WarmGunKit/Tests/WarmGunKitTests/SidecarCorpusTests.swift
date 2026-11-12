import Foundation
import Testing
@testable import WarmGunKit

@Suite struct SidecarCorpusTests {
    static let one = "1_sorted/alpha/portrait/video-one.mp4"
    static let two = "1_sorted/beta/landscape/video-two.mp4"
    static let oneSidecar = "portrait/alpha/video-one_topaz.json"
    static let twoSidecar = "landscape/beta/video-two_topaz.json"

    static func branch(_ listed: [String: Double]) -> SurveyedBranch {
        let files = listed.map { path, written in
            LibraryFile(path: path, fileID: 1, size: 100, modified: Date(timeIntervalSince1970: written),
                        duration: nil, videoCodec: nil, width: nil, height: nil)
        }
        return SurveyedBranch(path: "/mirror/kino/2D/AI", files: files,
                              index: SidecarIndex(branch: .ai, videoPaths: [one, two], listing: Array(listed.keys)))
    }

    @Test func theSavedCorpusKeepsEveryFieldASidecarCarriesForAReaderThatLearnsItLater() throws {
        let raw = Data(#"{"video": {"action": "site word", "labels": ["Alpha"], "later": {"x": 1}}}"#.utf8)
        var corpus = SidecarCorpus()
        corpus.keep(raw, for: "1_sorted/a/portrait/one.mp4", written: Date(timeIntervalSince1970: 1_000))

        let saved = try JSONDecoder().decode(SidecarCorpus.self, from: JSONEncoder().encode(corpus))

        #expect(saved == corpus)
        #expect(saved.sidecars["1_sorted/a/portrait/one.mp4"]?.labels == ["Alpha"])
    }

    @Test func aCorpusSavedAsDecodedSidecarsReadsAsNoneSoTheMirrorIsFetchedAgain() {
        let old = Data(#"{"1_sorted/a/portrait/one.mp4": {"video": {"action": "site word"}, "favorite": false}}"#.utf8)
        #expect((try? JSONDecoder().decode(SidecarCorpus.self, from: old)) == nil)
    }

    @Test func onlyASidecarNotYetKeptOrWrittenSinceItWasKeptIsFetchedAgain() throws {
        let branch = Self.branch([Self.oneSidecar: 1_000, Self.twoSidecar: 2_000])
        var corpus = SidecarCorpus()
        corpus.keep(Data("{}".utf8), for: Self.one, written: Date(timeIntervalSince1970: 1_000))
        corpus.keep(Data("{}".utf8), for: Self.two, written: Date(timeIntervalSince1970: 1_500))

        #expect(corpus.stale(in: branch).map(\.path) == [Self.twoSidecar])
        let saved = try JSONDecoder().decode(SidecarCorpus.self, from: JSONEncoder().encode(corpus))
        #expect(saved.stale(in: branch).map(\.path) == [Self.twoSidecar])
    }

    @Test func theGallerysFileReplacesEveryAIVideosRecordAndLeavesTheSidecarsOfTheRest() throws {
        let scene = "non_AI/bucket/scene-three.mkv"
        let gallery = GalleryRecords(libraryPath: "/alpha/videos/videos/2D/AI", genauFlicksFolder: nil,
                                     videoPaths: [Self.one, Self.two, scene])
        var corpus = SidecarCorpus()
        corpus.keep(Data(#"{"favorite": false}"#.utf8), for: Self.one, written: Date(timeIntervalSince1970: 1_000))
        corpus.keep(Data(#"{"favorite": true}"#.utf8), for: Self.two, written: Date(timeIntervalSince1970: 1_000))
        corpus.keep(Data(#"{"favorite": true}"#.utf8), for: scene, written: Date(timeIntervalSince1970: 1_000))

        corpus.keepGallery(Data(#"{"videos/videos/kino/2D/AI/portrait/alpha/video-one_topaz.mp4": {"favorite": true}}"#.utf8),
                           read: gallery, written: Date(timeIntervalSince1970: 2_000))

        #expect(corpus.sidecars[Self.one]?.favorite == true)
        #expect(corpus.sidecars[Self.two] == nil)
        #expect(corpus.sidecars[scene]?.favorite == true)
    }

    @Test func theGallerysFileIsFetchedAgainOnlyWhenTheMirrorListsItAsWrittenSinceItWasKept() throws {
        let gallery = GalleryRecords(libraryPath: "/alpha/videos/videos/2D/AI", genauFlicksFolder: nil, videoPaths: [Self.one])
        func listed(_ written: Double) -> LibraryFile {
            LibraryFile(path: "gallery_records.json", fileID: 9, size: 100, modified: Date(timeIntervalSince1970: written),
                        duration: nil, videoCodec: nil, width: nil, height: nil)
        }
        var corpus = SidecarCorpus()
        #expect(corpus.galleryIsStale(listed(1_000)))

        corpus.keepGallery(Data("{}".utf8), read: gallery, written: Date(timeIntervalSince1970: 1_000))
        let saved = try JSONDecoder().decode(SidecarCorpus.self, from: JSONEncoder().encode(corpus))

        #expect(!saved.galleryIsStale(listed(1_000)))
        #expect(saved.galleryIsStale(listed(1_500)))
    }
}
