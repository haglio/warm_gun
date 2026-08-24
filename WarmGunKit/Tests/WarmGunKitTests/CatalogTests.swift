import Foundation
import Testing
@testable import WarmGunKit

@Suite struct CatalogTests {
    static func file(_ path: String, id: Int64 = 1, size: Int64 = 2_000_000, seconds: Double? = 5.0) -> LibraryFile {
        LibraryFile(path: path, fileID: id, size: size, modified: Date(timeIntervalSince1970: 1_000),
                    duration: seconds, videoCodec: "h264", width: 752, height: 960)
    }

    @Test func keepsOnlyTheSortedOriginalsThatAreVideos() {
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/one.mp4", id: 1),
            Self.file("1_sorted/alpha/portrait/two.funscript", id: 2),
            Self.file("1_sorted/alpha/portrait/brokenmp4", id: 3),
            Self.file("2_outbox/upscaled_by_orientation/portrait/alpha/one_topaz.mp4", id: 4),
            Self.file("1_sorted/beta/landscape/three.MP4", id: 5),
        ])
        #expect(catalog.clips.map(\.path) == ["1_sorted/alpha/portrait/one.mp4", "1_sorted/beta/landscape/three.MP4"])
        #expect(catalog.clips[1].orientation == .landscape)
        #expect(catalog.clips[1].source == "beta")
        #expect(catalog.clips[1].stem == "three")
    }
}

extension CatalogTests {
    @Test func aGenauClipJoinsTheCatalogUnderItsOwnSource() {
        // Genau loops live outside the sorted tree, carry no orientation
        // folders, and are filed under the source "genau" — orientation comes
        // from their pixels when the listing has them, portrait otherwise.
        let wide = LibraryFile(path: "genau/clips/loop-one.mp4", fileID: 1, size: 2_000_000,
                               modified: Date(timeIntervalSince1970: 0), duration: nil,
                               videoCodec: nil, width: 1920, height: 1080)
        let unknown = LibraryFile(path: "genau/clips/loop-two.mp4", fileID: 2, size: 2_000_000,
                                  modified: Date(timeIntervalSince1970: 0), duration: nil,
                                  videoCodec: nil, width: nil, height: nil)
        let catalog = Catalog(files: [wide, unknown])
        #expect(catalog.clips.count == 2)
        #expect(catalog.clips[0].source == "genau")
        #expect(catalog.clips[0].orientation == .landscape)
        #expect(catalog.clips[0].stem == "loop-one")
        #expect(catalog.clips[1].orientation == .portrait)
    }
}

extension CatalogTests {
    @Test func nonAIScenesJoinTheCatalogAndTheirUpscaleVariantsDoNot() {
        // The non-AI tree holds each scene once as an original and again as a
        // huge processed upscale; the phone plays originals only.
        func file(_ path: String, width: Int? = nil, height: Int? = nil) -> LibraryFile {
            LibraryFile(path: path, fileID: 1, size: 300_000_000,
                        modified: Date(timeIntervalSince1970: 0), duration: nil,
                        videoCodec: nil, width: width, height: height)
        }
        let catalog = Catalog(files: [
            file("non_AI/alpha/scene-one.mp4", width: 1920, height: 1080),
            file("non_AI/alpha/tall-one.mp4", width: 1080, height: 1920),
            file("non_AI/alpha/processed/scene-one_apo8_iris2.mp4"),
            file("non_AI/alpha/scene-two_topaz.mp4"),
            file("non_AI/beta/deeper/scene-three.mp4"),
        ])
        #expect(catalog.clips.map(\.path) == ["non_AI/alpha/scene-one.mp4",
                                              "non_AI/alpha/tall-one.mp4",
                                              "non_AI/beta/deeper/scene-three.mp4"])
        #expect(catalog.clips[0].source == "non_AI")
        #expect(catalog.clips[0].orientation == .landscape)
        #expect(catalog.clips[1].orientation == .portrait)
        #expect(catalog.clips[2].stem == "scene-three")
    }
}

extension CatalogTests {
    @Test func aListingJoinsTheCatalogNamespaceUnderItsPrefix() {
        let file = LibraryFile(path: "loop-one.mp4", fileID: 3, size: 9, modified: Date(timeIntervalSince1970: 5),
                               duration: 2.0, videoCodec: "h264", width: 10, height: 20)
        let prefixed = file.prefixed("genau/clips/")
        #expect(prefixed.path == "genau/clips/loop-one.mp4")
        #expect(prefixed.fileID == 3)
        #expect(prefixed.modified == Date(timeIntervalSince1970: 5))
    }
}
