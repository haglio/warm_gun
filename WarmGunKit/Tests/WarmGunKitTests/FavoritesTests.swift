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
        // Stems are unique library-wide, so the original and the upscale mean one video.
        var favorites = Favorites()
        let added = favorites.insert(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(added)
        #expect(favorites.held == ["video-one"])
        #expect(favorites.contains(path: "1_sorted/alpha/portrait/video-one.mp4"))
        #expect(!favorites.contains(path: "1_sorted/alpha/portrait/video-two.mp4"))
    }
}

extension FavoritesTests {
    /// A favorite is a favorite in every lane. The desktop now flags genau
    /// loops and real scenes on their sidecars too, so a store that could only
    /// name a generated video would disagree with the flag on two thirds of the
    /// library. They are filed under their whole path, not a bare name, because
    /// nothing stops two files in that tree sharing one.
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
        // A path naming no file names no video.
        let nothing = favorites.insert(path: "genau/clips/")
        #expect(!nothing)
    }
}

extension FavoritesTests {
    @Test func adoptingTheDesktopsRecordAddsToTheStoreRatherThanReplacingIt() {
        // The desktop's record — the flag on the sidecars — is a snapshot from
        // before the trip, not the truth: what was favorited on the phone since
        // must survive it.
        var favorites = Favorites(held: ["video-one"])
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-one", "video-two"])
    }
}

extension FavoritesTests {
    /// The gap a plain union leaves: the desktop's snapshot is read again on
    /// every launch, so an unfavorite made away from home would be undone by
    /// the next one — and the trash gesture's two-step demotion could never
    /// reach its second step, because the first step keeps being re-taken.
    @Test func aStemLetGoOnThePhoneIsNotHandedBackByAStaleSnapshot() {
        var favorites = Favorites(held: ["video-one", "video-two"])

        let dropped = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        #expect(dropped)
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-two"])

        // Two launches, three, a hundred: the answer does not drift.
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(favorites.held == ["video-two"])
    }
}

extension FavoritesTests {
    /// The hold is released the moment the desktop agrees — its record no
    /// longer names the video, so the round trip is complete and the phone stops
    /// carrying the refusal. And a video held again on the phone is held, full
    /// stop: the refusal it once made says nothing about the choice it just did.
    @Test func theRefusalIsDroppedOnceTheDesktopAgreesOrThePhoneChangesItsMind() {
        var favorites = Favorites(held: ["video-one"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")

        favorites.adopt(flagged: ["video-two"], covering: ["video-one", "video-two"])  // the desktop caught up
        #expect(favorites.held == ["video-two"])
        favorites.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])  // and later re-favorited it
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
    /// The refusals outlive the app run, or a relaunch is exactly the moment
    /// the snapshot wins. A blob written before they existed still decodes.
    @Test func theRefusalsSurviveAJSONRoundTripAndAnOlderBlobStillDecodes() throws {
        var favorites = Favorites(held: ["video-one", "video-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")

        let data = try JSONEncoder().encode(favorites)
        var read = try JSONDecoder().decode(Favorites.self, from: data)
        read.adopt(flagged: ["video-one", "video-two"], covering: ["video-one", "video-two"])
        #expect(read.held == ["video-two"])

        // Written before the refusals existed, and under the old field name.
        let old = try JSONDecoder().decode(Favorites.self, from: Data(#"{"stems":["video-one"]}"#.utf8))
        #expect(old.held == ["video-one"])
    }
}

extension FavoritesTests {
    @Test func saysWhenNothingChangedSoTheJournalRecordsOnlyRealTurns() {
        // Locking a video that is already a favorite is not a second favorite.
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
    /// A record that could not speak for a lane is not the desktop agreeing.
    /// The corpus is fetched branch by branch and a branch that fails to answer
    /// is skipped, so absence from THAT record means the lane was missing —
    /// reading it as agreement would hand a dropped favorite straight back.
    @Test func aRefusalOutsideWhatTheRecordCoveredIsKept() {
        var favorites = Favorites(held: ["video-one", "genau/clips/2D/AI/loop-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/video-one.mp4")
        _ = favorites.remove(path: "genau/clips/2D/AI/loop-two.mp4")

        // Only the genau branch answered this time.
        favorites.adopt(flagged: [], covering: ["genau/clips/2D/AI/loop-two"])

        // The loop's refusal is settled; the video's is still owed an answer.
        favorites.adopt(flagged: ["video-one", "genau/clips/2D/AI/loop-two"],
                        covering: ["video-one", "genau/clips/2D/AI/loop-two"])
        #expect(favorites.held == ["genau/clips/2D/AI/loop-two"])
    }
}
