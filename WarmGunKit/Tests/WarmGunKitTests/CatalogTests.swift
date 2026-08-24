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
