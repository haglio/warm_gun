import Foundation
import Testing
@testable import WarmGunKit

/// The weight is the desktop's number, read and never recomputed, so every test
/// here is about *reading* one — what a sidecar says, and what silence means.
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
    /// A weight the sidecar cannot be read for is not a reason to throw the
    /// sidecar away: the same file carries the act the loops group by. Nor is a
    /// weight that could not be a multiplier — zero would silence a clip
    /// forever, and a negative one sorts FIRST in the draw, the exact inverse.
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
    /// The desktop writes the flag only when it is true, so absence is the
    /// whole of "not a favorite" — and anything that is not the literal `true`
    /// is absence too, rather than a decode failure that would cost the act.
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
    /// The corpus is kept on the phone between launches, so what the weight and
    /// the flag say has to survive the app's own encoder — not just the
    /// desktop's file. A launch reads that copy before any fetch lands.
    @Test func theStampSurvivesTheCorpusBeingPersistedAndReadBack() throws {
        let corpus = [
            "1_sorted/alpha/portrait/clip-one.mp4":
                Sidecar(video: ["action": "waving"], sourceImage: nil,
                        watch: Sidecar.Watch(weight: 0.125), favorite: true),
            "genau/clips/loop-two.mp4":
                Sidecar(video: ["action": "turning"], sourceImage: nil),
        ]

        let data = try JSONEncoder().encode(corpus)
        let read = try JSONDecoder().decode([String: Sidecar].self, from: data)

        #expect(read == corpus)
        #expect(read["1_sorted/alpha/portrait/clip-one.mp4"]?.watchWeight == 0.125)
        #expect(read["1_sorted/alpha/portrait/clip-one.mp4"]?.favorite == true)
        #expect(read["genau/clips/loop-two.mp4"]?.watchWeight == nil)
        #expect(read["genau/clips/loop-two.mp4"]?.favorite == false)
    }
}

extension WatchWeightsTests {
    /// What the draw asks: one number per clip. A clip nobody has watched, one
    /// whose sidecar never arrived, and one whose stamp could not be read all
    /// answer the same — neutral — because none of them is evidence.
    @Test func aClipWeighsWhatItsSidecarSaysAndOtherwiseWeighsOne() {
        let weights = WatchWeights(sidecars: [
            "1_sorted/alpha/portrait/clip-one.mp4":
                Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 8.0)),
            "1_sorted/beta/landscape/clip-two.mp4":
                Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125)),
            "genau/clips/loop-three.mp4": Sidecar(video: nil, sourceImage: nil),
        ])

        #expect(weights.weight(for: "1_sorted/alpha/portrait/clip-one.mp4") == 8.0)
        #expect(weights.weight(for: "1_sorted/beta/landscape/clip-two.mp4") == 0.125)
        #expect(weights.weight(for: "genau/clips/loop-three.mp4") == 1.0)
        #expect(weights.weight(for: "non_AI/bucket/scene-four.mp4") == 1.0)
    }
}

extension WatchWeightsTests {
    /// Inclusion is the continuous version of marking a clip weird: a clip at or
    /// above neutral always makes the build, and one below it sits out in
    /// proportion to how far below it has fallen.
    @Test func inclusionKeepsEveryNeutralOrLovedClipAndThinsTheRest() {
        var rng = PlaylistSeededRNG(seed: 3)
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 1.0, rng: &rng) })
        #expect((0..<100).allSatisfy { _ in Weighting.passesInclusion(weight: 8.0, rng: &rng) })

        let kept = (0..<200).filter { _ in Weighting.passesInclusion(weight: 0.5, rng: &rng) }.count
        #expect(kept > 60 && kept < 140)
        #expect(!(0..<200).contains { _ in Weighting.passesInclusion(weight: 0.0, rng: &rng) })
    }
}

extension WatchWeightsTests {
    /// A shuffle reorders; it never gains or loses a clip — with equal weights
    /// it is exactly a uniform shuffle of the same set.
    @Test func theWeightedShuffleKeepsEveryItemAndAcceptsAnEmptyList() {
        var rng = PlaylistSeededRNG(seed: 1)
        let stems = (0..<10).map { "clip-\($0)" }

        let shuffled = Weighting.weightedShuffle(stems, weight: { _ in 1.0 }, rng: &rng)

        #expect(shuffled.sorted() == stems.sorted())
        #expect(Weighting.weightedShuffle([String](), weight: { _ in 1.0 }, rng: &rng).isEmpty)
    }
}

extension WatchWeightsTests {
    /// The point of the weighting: over many builds the loved clip is the one
    /// that opens the playlist far more often than the chronically skipped one.
    @Test func theWeightedShuffleFrontLoadsTheHeavierItem() {
        var rng = PlaylistSeededRNG(seed: 7)
        let weights = ["clip-heavy": 8.0, "clip-light": 0.125]

        let heavyFirst = (0..<200).filter { _ in
            Weighting.weightedShuffle(["clip-light", "clip-heavy"], weight: { weights[$0]! }, rng: &rng).first == "clip-heavy"
        }.count

        #expect(heavyFirst > 150)
    }
}

extension WatchWeightsTests {
    @Test func aWeightThatIsNotAPositiveNumberShufflesAsNeutral() {
        // The desktop coerces a dead weight to 1.0 before drawing; a negative or
        // non-finite one from a foreign caller must not front-load the item (a
        // negative key sorts first — the exact inverse of the intent).
        var rng = PlaylistSeededRNG(seed: 3)
        var leads = 0
        for _ in 0..<200 {
            let order = Weighting.weightedShuffle(["a", "b", "c", "d"],
                                                  weight: { $0 == "d" ? -1.0 : 1.0 }, rng: &rng)
            if order.first == "d" { leads += 1 }
        }
        #expect((20...80).contains(leads))  // ~1 in 4 of 200; -1.0 raw would be 200 of 200
    }
}
