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
}
