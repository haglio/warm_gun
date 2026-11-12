import Foundation
import Testing
@testable import WarmGunKit

@Suite struct GalleryRecordsTests {
    static let library = "/alpha/videos/videos/2D/AI"
    static let one = "1_sorted/alpha/portrait/video-one.mkv"

    static func file(_ json: String) -> Data { Data(json.utf8) }

    @Test func anOriginalsRecordIsTheGalleryEntryOfItsUpscale() throws {
        let gallery = GalleryRecords(libraryPath: Self.library, genauFlicksFolder: "loops", videoPaths: [Self.one])
        let records = gallery.records(in: Self.file(#"""
            {"videos/videos/kino/2D/AI/portrait/alpha/video-one_topaz.mp4":
              {"video": {"seed": 7, "labels": ["Alpha"], "type": "excerpt"}, "favorite": true, "watch": {"weight": 2.5}}}
            """#))

        let sidecar = try JSONDecoder().decode(Sidecar.self, from: #require(records[Self.one]))
        #expect(sidecar.labels == ["Alpha"])
        #expect(sidecar.video?["type"] == "excerpt")
        #expect(sidecar.favorite)
        #expect(sidecar.watchWeight == 2.5)
    }

    @Test func onlyTheAIVideosAreTheGallerysAndAGenauFlickIsKeyedInsideItsFolder() {
        let gallery = GalleryRecords(libraryPath: Self.library, genauFlicksFolder: "loops", videoPaths: [
            Self.one,
            "genau/clips/2D/AI/loop-three.mp4",
            "genau/clips/2D/non_AI/loop-four.mp4",
            "genau/clips/VR/loop-five.mp4",
            "non_AI/bucket/inner/scene-six.mkv",
        ])

        #expect(gallery.videosByKey == [
            "videos/videos/kino/2D/AI/portrait/alpha/video-one_topaz.mp4": Self.one,
            "videos/videos/genau/loops/2D/AI/loop-three.mp4": "genau/clips/2D/AI/loop-three.mp4",
        ])
    }
}
