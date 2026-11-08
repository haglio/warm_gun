import Foundation
import Testing
@testable import WarmGunKit

@Suite struct SidecarIndexTests {
    static let videos = [
        "1_sorted/alpha/portrait/video-one.mp4",
        "1_sorted/beta/landscape/video-two.mp4",
        "genau/clips/2D/AI/loop-three.mp4",
        "non_AI/bucket/inner/scene-four.mkv",
    ]

    @Test func keepsTheListedSidecarsThatNameAVideoAndDropsTheRest() {
        let index = SidecarIndex(branch: .ai, videoPaths: Self.videos, listing: [
            "portrait/alpha/video-one_topaz.json",
            "landscape/beta/video-two_topaz.json",
            "portrait/alpha/video-gone_topaz.json",
            "landscape/alpha/video-one_topaz.json",
            "not-a-sidecar.txt",
        ])

        #expect(index.videosByListedSidecar == [
            "portrait/alpha/video-one_topaz.json":
                "1_sorted/alpha/portrait/video-one.mp4",
            "landscape/beta/video-two_topaz.json":
                "1_sorted/beta/landscape/video-two.mp4",
        ])
    }
}

extension SidecarIndexTests {
    @Test func theGenauAndNonAILanesJoinOnTheMirroredPath() {
        let genau = SidecarIndex(branch: .genau, videoPaths: Self.videos,
                                 listing: ["2D/AI/loop-three.json", "2D/AI/loop-absent.json"])
        let scenes = SidecarIndex(branch: .nonAI, videoPaths: Self.videos,
                                  listing: ["bucket/inner/scene-four.json", "bucket/other.json"])

        #expect(genau.videosByListedSidecar
                == ["2D/AI/loop-three.json": "genau/clips/2D/AI/loop-three.mp4"])
        #expect(scenes.videosByListedSidecar
                == ["bucket/inner/scene-four.json": "non_AI/bucket/inner/scene-four.mkv"])
    }
}
