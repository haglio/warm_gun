import Foundation
import Testing
@testable import WarmGunKit

/// The join between one branch of the metadata mirror and the videos the phone
/// can actually play. Every fixture name here is invented.
@Suite struct SidecarIndexTests {
    static let videos = [
        "1_sorted/alpha/portrait/video-one.mp4",
        "1_sorted/beta/landscape/video-two.mp4",
        "genau/clips/2D/AI/loop-three.mp4",
        "non_AI/bucket/inner/scene-four.mkv",
    ]

    /// Only the sidecars that speak for a video in the catalog are worth having,
    /// and each is named by the listing's own relative path — which is what the
    /// fetch asks the server for.
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
    /// The other two lanes mirror straight across, and a scene keeps whatever
    /// extension it has — the sidecar drops it, so the join cannot assume .mp4.
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
    /// A zip entry carries whatever root the server chose to name the archive
    /// after, so an entry is matched by its tail against the paths the listing
    /// already gave — never by assuming a prefix.
    @Test func aZipEntryIsMatchedByItsTailWhateverRootTheServerChose() {
        let index = SidecarIndex(branch: .ai, videoPaths: Self.videos, listing: [
            "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json",
        ])
        let video = "1_sorted/alpha/portrait/video-one.mp4"

        #expect(index.video(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        #expect(index.video(forZipEntry: "AI/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        #expect(index.video(forZipEntry: "whatever/2D/AI/2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.json") == video)
        // A tail that only looks similar is not a match: the boundary has to
        // fall on a separator, or `x/video-one_topaz.json` would claim it.
        #expect(index.video(forZipEntry: "alpha/video-one_topaz.json") == nil)
        #expect(index.video(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/video-gone_topaz.json") == nil)
    }
}
