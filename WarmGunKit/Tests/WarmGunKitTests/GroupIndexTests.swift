import Foundation
import Testing
@testable import WarmGunKit

/// The desktop's grouping, ported field for field from
/// `fun_time/media_metadata.py`: an ACTION group holds the seed fixed and lets
/// the action vary; a SEED family holds the action fixed and lets the seed vary.
/// Every fixture is fabricated.
@Suite struct GroupIndexTests {
    static func sidecar(action: String? = "alpha", prompt: String? = "a scene",
                        videoSeed: String? = "111", image: Bool = false,
                        imageSeed: String? = "901", positivePrompt: String? = "a subject") -> Sidecar {
        var video: [String: String] = [:]
        if let action { video["action"] = action }
        if let prompt { video["prompt"] = prompt }
        if let videoSeed { video["seed"] = videoSeed }
        video["model"] = "m1"; video["resolution"] = "720p"
        video["aspect_ratio"] = "9:16"; video["quality"] = "high"
        var sourceImage: [String: String]? = nil
        if image {
            var block: [String: String] = ["model": "im1", "resolution": "1080",
                                           "aspect_ratio": "9:16", "quality": "high",
                                           "style": "s", "creativity": "3",
                                           "negative_prompt": "none"]
            if let imageSeed { block["seed"] = imageSeed }
            if let positivePrompt { block["positive_prompt"] = positivePrompt }
            sourceImage = block
        }
        return Sidecar(video: video, sourceImage: sourceImage)
    }

    @Test func textToVideoTwinsShareAnActionGroupAcrossActions() {
        // Same prompt/params/SEED, different actions: one subject doing different
        // things — the action group. A different seed is a different subject.
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(action: "alpha"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: "beta"),
            "1_sorted/a/portrait/three.mp4": Self.sidecar(action: "beta", videoSeed: "222"),
        ])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/one.mp4")
                == ["1_sorted/a/portrait/one.mp4", "1_sorted/a/portrait/two.mp4"])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/three.mp4")
                == ["1_sorted/a/portrait/three.mp4"])
        #expect(!index.isEmpty)
        #expect(GroupIndex(sidecars: [:]).isEmpty)
    }

    @Test func seedFamiliesHoldTheActionFixedAndLetTheSeedVary() {
        // Same prompt/params/ACT, different seeds — and the desktop narrows
        // the family to the anchor's own action with normalized comparison, so a
        // casing variant does not split the row.
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(action: "Alpha", videoSeed: "111"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: "alpha", videoSeed: "222"),
            "1_sorted/a/portrait/three.mp4": Self.sidecar(action: "beta", videoSeed: "333"),
        ])
        #expect(index.seedVideos(of: "1_sorted/a/portrait/one.mp4")
                == ["1_sorted/a/portrait/one.mp4", "1_sorted/a/portrait/two.mp4"])
    }

    @Test func imageToVideoVideosGroupOnTheSourceImageIdentity() {
        // With a source_image block the IMAGE's identity is the key: the image
        // seed varies the seed family; the actions vary within one image.
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(action: "alpha", image: true, imageSeed: "901"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: "beta", image: true, imageSeed: "901"),
            "1_sorted/a/portrait/three.mp4": Self.sidecar(action: "alpha", image: true, imageSeed: "902"),
        ])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/one.mp4")
                == ["1_sorted/a/portrait/one.mp4", "1_sorted/a/portrait/two.mp4"])
        // The image family spans actions, so the seed row narrows to the anchor's.
        #expect(index.seedVideos(of: "1_sorted/a/portrait/one.mp4")
                == ["1_sorted/a/portrait/one.mp4", "1_sorted/a/portrait/three.mp4"])
    }

    @Test func aVideoWithoutTheKeyFieldsBelongsToNoGroup() {
        // No sidecar, no prompt, or no seed: the desktop returns None — the
        // video loops as itself alone.
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(prompt: nil),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(videoSeed: nil),
        ])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/one.mp4") == ["1_sorted/a/portrait/one.mp4"])
        #expect(index.seedVideos(of: "1_sorted/a/portrait/two.mp4") == ["1_sorted/a/portrait/two.mp4"])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/unknown.mp4") == ["1_sorted/a/portrait/unknown.mp4"])
    }

    @Test func sidecarsDecodeFromTheRealJSONShape() throws {
        let json = Data("""
        {"video": {"action": "alpha", "prompt": "a scene", "seed": "111", "model": "m1"},
         "source_image": {"positive_prompt": "a subject", "seed": "901", "model": "im1"}}
        """.utf8)
        let sidecar = try JSONDecoder().decode(Sidecar.self, from: json)
        #expect(sidecar.video?["action"] == "alpha")
        #expect(sidecar.sourceImage?["seed"] == "901")
        let stub = try JSONDecoder().decode(Sidecar.self, from: Data(#"{"video": {"action": "beta"}}"#.utf8))
        #expect(stub.video?["action"] == "beta")
        #expect(stub.sourceImage == nil)
    }
}

extension GroupIndexTests {
    @Test func handsOutTheNormalizedActionsForTheBuildToFilterOn() {
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(action: "Very  Special"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: nil),
        ])
        #expect(index.actionsByPath == ["1_sorted/a/portrait/one.mp4": "very special"])
    }
}

extension GroupIndexTests {
    @Test func theLoopControlsGroupStopsWalkTheirGroupsAndItsPlaybackStopsWalkNone() {
        let one = "1_sorted/a/portrait/one.mp4"
        let index = GroupIndex(sidecars: [
            one: Self.sidecar(action: "alpha", videoSeed: "111"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: "beta", videoSeed: "111"),
            "1_sorted/a/portrait/three.mp4": Self.sidecar(action: "alpha", videoSeed: "222"),
        ])
        #expect(index.group(.action, of: one) == [one, "1_sorted/a/portrait/two.mp4"])
        #expect(index.group(.seed, of: one) == [one, "1_sorted/a/portrait/three.mp4"])
        #expect(index.group(.all, of: one) == nil)
        #expect(index.group(.single, of: one) == nil)
    }
}

extension GroupIndexTests {
    @Test func onlyAGroupHoldingAnotherVideoCanBeLoopedWhileAllAndOneAlwaysCan() {
        let one = "1_sorted/a/portrait/one.mp4"
        let index = GroupIndex(sidecars: [
            one: Self.sidecar(action: "alpha", videoSeed: "111"),
            "1_sorted/a/portrait/two.mp4": Self.sidecar(action: "beta", videoSeed: "111"),
        ])
        #expect(index.canLoop(.action, from: one))
        #expect(!index.canLoop(.seed, from: one))
        #expect(index.canLoop(.all, from: one))
        #expect(index.canLoop(.single, from: one))
        #expect(!GroupIndex(sidecars: [:]).canLoop(.action, from: one))
    }
}

extension GroupIndexTests {
    @Test func aFieldOutsideTheKeysDoesNotSplitAGroup() {
        var later = Self.sidecar(action: "beta").video ?? [:]
        later["created"] = "2026-01-02"
        let index = GroupIndex(sidecars: [
            "1_sorted/a/portrait/one.mp4": Self.sidecar(action: "alpha"),
            "1_sorted/a/portrait/two.mp4": Sidecar(video: later, sourceImage: nil),
        ])
        #expect(index.actionVideos(of: "1_sorted/a/portrait/one.mp4")
                == ["1_sorted/a/portrait/one.mp4", "1_sorted/a/portrait/two.mp4"])
    }

    @Test func normalizedTextCollapsesWhitespaceLowersCaseAndReadsNilAsEmpty() {
        #expect(GroupIndex.normText("  Big\t ALPHA\n") == "big alpha")
        #expect(GroupIndex.normText(nil) == "")
    }
}
