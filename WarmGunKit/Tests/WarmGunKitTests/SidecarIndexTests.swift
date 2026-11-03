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
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json",
            "2_outbox/upscaled_by_orientation/landscape/beta/video-two_topaz.json",
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-gone_topaz.json",
            "2_outbox/trash/video-one_topaz.json",
            "not-a-sidecar.txt",
        ])

        #expect(index.videosByListedSidecar == [
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json":
                "1_sorted/alpha/portrait/video-one.mp4",
            "2_outbox/upscaled_by_orientation/landscape/beta/video-two_topaz.json":
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

extension SidecarIndexTests {
    @Test func aZipEntryIsMatchedByItsTailWhateverRootTheServerChose() {
        let index = SidecarIndex(branch: .ai, videoPaths: Self.videos, listing: [
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json",
        ])
        let video = "1_sorted/alpha/portrait/video-one.mp4"

        #expect(index.video(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        #expect(index.video(forZipEntry: "AI/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        #expect(index.video(forZipEntry: "whatever/2D/AI/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        #expect(index.video(forZipEntry: "alpha/video-one_topaz.json") == nil)
        #expect(index.video(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/video-gone_topaz.json") == nil)
    }
}

extension SidecarIndexTests {
    @Test func aZipEntryMatchesOnlyWhereItsTailStartsOnASeparator() {
        let index = SidecarIndex(branch: .ai, videoPaths: Self.videos, listing: [
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json",
        ])
        #expect(index.video(forZipEntry: "x2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == nil)
    }
}
