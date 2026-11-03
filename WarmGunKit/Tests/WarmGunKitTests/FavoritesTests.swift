import Foundation
import Testing
@testable import WarmGunKit

@Suite struct FavoritesTests {
    @Test func aGenauFavoriteFromBeforeTheSplitIsCarriedToWhereTheFlickIsNow() {
        var favorites = Favorites(held: ["genau/clips/loop-one", "video-one"],
                                  released: ["genau/clips/loop-two"])

        favorites.rekeyFlatGenau(against: ["genau/clips/2D/AI/loop-one",
                                           "genau/clips/2D/non_AI/loop-two"])

        #expect(favorites.held == ["genau/clips/2D/AI/loop-one", "video-one"])
        #expect(favorites.released == ["genau/clips/2D/non_AI/loop-two"])
    }

    @Test func keepsAVideoByItsStemSoEitherRenditionAsksTheSameQuestion() {
        var favorites = Favorites()
        let added = favorites.insert(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(added)
        #expect(favorites.held == ["video-one"])
        #expect(favorites.contains(path: "1_sorted/alpha/portrait/video-one.mp4"))
        #expect(!favorites.contains(path: "1_sorted/alpha/portrait/video-two.mp4"))
    }
}

extension FavoritesTests {
    @Test func aLoopOrASceneCanBeHeldJustAsAGeneratedVideoCan() {
        var favorites = Favorites()

        let heldLoop = favorites.insert(path: "genau/clips/2D/AI/loop-two.mp4")
        let heldScene = favorites.insert(path: "non_AI/bucket/inner/scene-three.mkv")
        #expect(heldLoop)
        #expect(heldScene)

        #expect(favorites.held == ["genau/clips/2D/AI/loop-two", "non_AI/bucket/inner/scene-three"])
        #expect(favorites.contains(path: "genau/clips/2D/AI/loop-two.mp4"))
        #expect(favorites.contains(path: "non_AI/bucket/inner/scene-three.mkv"))

        let dropped = favorites.remove(path: "genau/clips/2D/AI/loop-two.mp4")
        #expect(dropped)
        #expect(!favorites.contains(path: "genau/clips/2D/AI/loop-two.mp4"))
        let nothing = favorites.insert(path: "genau/clips/")
        #expect(!nothing)
    }
}

extension FavoritesTests {
    @Test func adoptingTheDesktopsRecordAddsToTheStoreRatherThanReplacingIt() {
        var favorites = Favorites(held: ["video-one"])
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-one", "video-two"])
    }
}

extension FavoritesTests {
    @Test func aStemLetGoOnThePhoneIsNotHandedBackByAStaleSnapshot() {
        var favorites = Favorites(held: ["video-one", "video-two"])

        let dropped = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(dropped)
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-two"])

        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-two"])
    }
}

extension FavoritesTests {
    @Test func theRefusalIsDroppedOnceTheDesktopAgreesOrThePhoneChangesItsMind() {
        var favorites = Favorites(held: ["video-one"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")

        favorites.adopt(flagged: ["video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-two"])
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-one", "video-two"])

        var again = Favorites(held: ["video-one"])
        _ = again.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        let heldAgain = again.insert(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(heldAgain)
        again.adopt(flagged: ["video-one"], covering: ["video-one"])
        #expect(again.held == ["video-one"])
    }
}

extension FavoritesTests {
    @Test func theRefusalsSurviveAJSONRoundTripAndAnOlderBlobStillDecodes() throws {
        var favorites = Favorites(held: ["video-one", "video-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")

        let data = try JSONEncoder().encode(favorites)
        var read = try JSONDecoder().decode(Favorites.self, from: data)
        read.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(read.held == ["video-two"])

        let old = try JSONDecoder().decode(Favorites.self, from: Data(#"{"stems":["video-one"]}"#.utf8))
        #expect(old.held == ["video-one"])
    }
}

extension FavoritesTests {
    @Test func saysWhenNothingChangedSoTheJournalRecordsOnlyRealTurns() {
        var favorites = Favorites(held: ["video-one"])
        let again = favorites.insert(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(!again)
        #expect(favorites.held == ["video-one"])

        let removed = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(removed)
        #expect(favorites.held.isEmpty)
        let removedTwice = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(!removedTwice)
    }
}

extension FavoritesTests {
    @Test func aRefusalOutsideWhatTheRecordCoveredIsKept() {
        var favorites = Favorites(held: ["video-one", "genau/clips/2D/AI/loop-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        _ = favorites.remove(path: "genau/clips/2D/AI/loop-two.mp4")

        favorites.adopt(flagged: [], covering: ["genau/clips/2D/AI/loop-two"])

        favorites.adopt(flagged: ["video-one", "genau/clips/2D/AI/loop-two"],
                        covering: ["video-one", "genau/clips/2D/AI/loop-two"])
        #expect(favorites.held == ["genau/clips/2D/AI/loop-two"])
    }
}
