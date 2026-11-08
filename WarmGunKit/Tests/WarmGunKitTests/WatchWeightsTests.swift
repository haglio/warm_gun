import Foundation
import Testing
@testable import WarmGunKit

@Suite struct WatchWeightsTests {
    @Test func aSidecarCarriesTheStampedWeight() throws {
        let json = Data(#"""
        {"video": {"type": "short", "action": "waving"},
         "watch": {"completions": 6, "skips": 3, "locks": 0, "weight": 2.0}}
        """#.utf8)

        let sidecar = try JSONDecoder().decode(Sidecar.self, from: json)

        #expect(sidecar.watchWeight == 2.0)
    }
}

extension WatchWeightsTests {
    @Test func aWeightThatCannotBeUsedReadsAsNoWeightAndKeepsTheRestOfTheSidecar() throws {
        let bodies = [
            #"{"video": {"action": "waving"}}"#,
            #"{"video": {"action": "waving"}, "watch": {"completions": 2}}"#,
            #"{"video": {"action": "waving"}, "watch": {"weight": "2.0"}}"#,
            #"{"video": {"action": "waving"}, "watch": {"weight": 0}}"#,
            #"{"video": {"action": "waving"}, "watch": {"weight": -4}}"#,
            #"{"video": {"action": "waving"}, "watch": []}"#,
        ]

        for body in bodies {
            let sidecar = try JSONDecoder().decode(Sidecar.self, from: Data(body.utf8))
            #expect(sidecar.watchWeight == nil, "\(body)")
            #expect(sidecar.video?["action"] == "waving", "\(body)")
        }
    }
}

extension WatchWeightsTests {
    @Test func aSidecarFlagsAFavoriteOnlyBySayingSo() throws {
        let cases = [
            (#"{"video": {"action": "waving"}, "favorite": true}"#, true),
            (#"{"video": {"action": "waving"}, "favorite": false}"#, false),
            (#"{"video": {"action": "waving"}}"#, false),
            (#"{"video": {"action": "waving"}, "favorite": "yes"}"#, false),
        ]

        for (body, expected) in cases {
            let sidecar = try JSONDecoder().decode(Sidecar.self, from: Data(body.utf8))
            #expect(sidecar.favorite == expected, "\(body)")
            #expect(sidecar.video?["action"] == "waving", "\(body)")
        }
    }
}

extension WatchWeightsTests {
    @Test func theStampSurvivesTheCorpusBeingPersistedAndReadBack() throws {
        var corpus = SidecarCorpus()
        corpus.keep(Data(#"{"video": {"action": "waving"}, "watch": {"weight": 0.125}, "favorite": true}"#.utf8),
                    for: "1_sorted/alpha/portrait/video-one.mp4", written: Date(timeIntervalSince1970: 1_000))
        corpus.keep(Data(#"{"video": {"action": "turning"}}"#.utf8),
                    for: "genau/clips/2D/AI/loop-two.mp4", written: Date(timeIntervalSince1970: 1_000))

        let data = try JSONEncoder().encode(corpus)
        let read = try JSONDecoder().decode(SidecarCorpus.self, from: data).sidecars

        #expect(read["1_sorted/alpha/portrait/video-one.mp4"]?.watchWeight == 0.125)
        #expect(read["1_sorted/alpha/portrait/video-one.mp4"]?.favorite == true)
        #expect(read["genau/clips/2D/AI/loop-two.mp4"]?.watchWeight == nil)
        #expect(read["genau/clips/2D/AI/loop-two.mp4"]?.favorite == false)
    }
}

extension WatchWeightsTests {
    @Test func aVideoWeighsWhatItsSidecarSaysAndOtherwiseWeighsOne() {
        let weights = WatchWeights(sidecars: [
            "1_sorted/alpha/portrait/video-one.mp4":
                Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 8.0)),
            "1_sorted/beta/landscape/video-two.mp4":
                Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125)),
            "genau/clips/2D/AI/loop-three.mp4": Sidecar(video: nil, sourceImage: nil),
        ])

        #expect(weights.weight(for: "1_sorted/alpha/portrait/video-one.mp4") == 8.0)
        #expect(weights.weight(for: "1_sorted/beta/landscape/video-two.mp4") == 0.125)
        #expect(weights.weight(for: "genau/clips/2D/AI/loop-three.mp4") == 1.0)
        #expect(weights.weight(for: "non_AI/bucket/scene-four.mp4") == 1.0)
    }
}

extension WatchWeightsTests {
    @Test func aNumberInTheVideoBlockCostsNeitherTheBlockNorTheSidecar() throws {
        let json = Data(#"""
        {"video": {"type": "short", "duration_seconds": 4.2, "seed": 12345,
                   "action": "waving", "wrong_action": null, "video": {"of": "x"}},
         "watch": {"completions": 3, "skips": 0, "locks": 1, "weight": 4.0},
         "favorite": true}
        """#.utf8)

        let sidecar = try JSONDecoder().decode(Sidecar.self, from: json)

        #expect(sidecar.video?["action"] == "waving")
        #expect(sidecar.video?["type"] == "short")
        #expect(sidecar.video?["duration_seconds"] == "4.2")
        #expect(sidecar.video?["seed"] == "12345")
        #expect(sidecar.video?["wrong_action"] == nil)
        #expect(sidecar.video?["video"] == nil)
        #expect(sidecar.watchWeight == 4.0)
        #expect(sidecar.favorite)
    }
}

extension WatchWeightsTests {
    @Test func aWholeNumberReadsBackWithoutAFractionalPart() throws {
        let json = Data(#"{"video": {"duration_seconds": 2.0, "seed": 12345}}"#.utf8)

        let sidecar = try JSONDecoder().decode(Sidecar.self, from: json)

        #expect(sidecar.video?["duration_seconds"] == "2")
        #expect(sidecar.video?["seed"] == "12345")
    }
}

extension WatchWeightsTests {
    @Test func inclusionKeepsEveryNeutralOrLovedVideoAndThinsTheRest() {
        var rng = PlaylistSeededRNG(seed: 3)
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 1.0, rng: &rng) })
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 8.0, rng: &rng) })

        let kept = (0..<200).filter { _ in Weighting.passesInclusion(weight: 0.5, rng: &rng) }.count
        #expect(kept > 60 && kept < 140)
        #expect(!(0..<200).contains { _ in Weighting.passesInclusion(weight: 0.0, rng: &rng) })
    }
}

extension WatchWeightsTests {
    @Test func theWeightedShuffleKeepsEveryItemAndAcceptsAnEmptyList() {
        var rng = PlaylistSeededRNG(seed: 1)
        let stems = (0..<10).map { "video-\($0)" }

        let shuffled = Weighting.weightedShuffle(stems, weight: { _ in 1.0 }, rng: &rng)

        #expect(shuffled.sorted() == stems.sorted())
        #expect(Weighting.weightedShuffle([String](), weight: { _ in 1.0 }, rng: &rng).isEmpty)
    }
}

extension WatchWeightsTests {
    @Test func theWeightedShuffleFrontLoadsTheHeavierItem() {
        var rng = PlaylistSeededRNG(seed: 7)
        let weights = ["video-heavy": 8.0, "video-light": 0.125]

        let heavyFirst = (0..<200).filter { _ in
            Weighting.weightedShuffle(["video-light", "video-heavy"], weight: { weights[$0]! }, rng: &rng).first == "video-heavy"
        }.count

        #expect(heavyFirst > 150)
    }
}

extension WatchWeightsTests {
    @Test func aWeightThatIsNotAPositiveNumberShufflesAsNeutral() {
        var rng = PlaylistSeededRNG(seed: 3)
        var leads = 0
        for _ in 0..<200 {
            let order = Weighting.weightedShuffle(["a", "b", "c", "d"],
                                                  weight: { $0 == "d" ? -1.0 : 1.0 }, rng: &rng)
            if order.first == "d" { leads += 1 }
        }
        #expect((20...80).contains(leads))
    }
}
