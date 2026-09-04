import Foundation
import Testing
@testable import WarmGunKit

/// The join between one branch of the metadata mirror and the clips the phone
/// can actually play. Every fixture name here is invented.
@Suite struct SidecarIndexTests {
    static let clips = [
        "1_sorted/alpha/portrait/clip-one.mp4",
        "1_sorted/beta/landscape/clip-two.mp4",
        "genau/clips/loop-three.mp4",
        "non_AI/bucket/inner/scene-four.mkv",
    ]

    /// Only the sidecars that speak for a clip in the catalog are worth having,
    /// and each is named by the listing's own relative path — which is what the
    /// fetch asks the server for.
    @Test func keepsTheListedSidecarsThatNameAClipAndDropsTheRest() {
        let index = SidecarIndex(branch: .ai, clipPaths: Self.clips, listing: [
            "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json",
            "2_outbox/upscaled_by_orientation/landscape/beta/clip-two_topaz.json",
            "2_outbox/upscaled_by_orientation/portrait/alpha/clip-gone_topaz.json",
            "2_outbox/kinda_weird/clip-one_topaz.json",
            "not-a-sidecar.txt",
        ])

        #expect(index.clipsByListedSidecar == [
            "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json":
                "1_sorted/alpha/portrait/clip-one.mp4",
            "2_outbox/upscaled_by_orientation/landscape/beta/clip-two_topaz.json":
                "1_sorted/beta/landscape/clip-two.mp4",
        ])
    }
}

extension SidecarIndexTests {
    /// The other two lanes mirror straight across, and a scene keeps whatever
    /// extension it has — the sidecar drops it, so the join cannot assume .mp4.
    @Test func theGenauAndNonAILanesJoinOnTheMirroredPath() {
        let genau = SidecarIndex(branch: .genau, clipPaths: Self.clips,
                                 listing: ["loop-three.json", "loop-absent.json"])
        let scenes = SidecarIndex(branch: .nonAI, clipPaths: Self.clips,
                                  listing: ["bucket/inner/scene-four.json", "bucket/other.json"])

        #expect(genau.clipsByListedSidecar == ["loop-three.json": "genau/clips/loop-three.mp4"])
        #expect(scenes.clipsByListedSidecar
                == ["bucket/inner/scene-four.json": "non_AI/bucket/inner/scene-four.mkv"])
    }
}

extension SidecarIndexTests {
    /// A zip entry carries whatever root the server chose to name the archive
    /// after, so an entry is matched by its tail against the paths the listing
    /// already gave — never by assuming a prefix.
    @Test func aZipEntryIsMatchedByItsTailWhateverRootTheServerChose() {
        let index = SidecarIndex(branch: .ai, clipPaths: Self.clips, listing: [
            "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json",
        ])
        let clip = "1_sorted/alpha/portrait/clip-one.mp4"

        #expect(index.clip(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json") == clip)
        #expect(index.clip(forZipEntry: "AI/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json") == clip)
        #expect(index.clip(forZipEntry: "whatever/2D/AI/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json") == clip)
        // A tail that only looks similar is not a match: the boundary has to
        // fall on a separator, or `x/clip-one_topaz.json` would claim it.
        #expect(index.clip(forZipEntry: "alpha/clip-one_topaz.json") == nil)
        #expect(index.clip(forZipEntry: "2_outbox/upscaled_by_orientation/portrait/alpha/clip-gone_topaz.json") == nil)
    }
}
