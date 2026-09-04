import Foundation
import Testing
@testable import WarmGunKit

@Suite struct FavoritesTests {
    @Test func keepsAClipByItsStemSoEitherRenditionAsksTheSameQuestion() {
        // Stems are unique library-wide, which is what lets the phone's store and
        // the desktop's favs.csv — which knows only upscale names — mean one clip.
        var favorites = Favorites()
        let added = favorites.insert(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(added)
        #expect(favorites.held == ["clip-one"])
        #expect(favorites.contains(path: "1_sorted/alpha/portrait/clip-one.mp4"))
        #expect(!favorites.contains(path: "1_sorted/alpha/portrait/clip-two.mp4"))
    }
}

extension FavoritesTests {
    /// A favorite is a favorite in every lane. The desktop now flags genau
    /// loops and real scenes on their sidecars too, so a store that could only
    /// name a generated clip would disagree with the flag on two thirds of the
    /// library. They are filed under their whole path, not a bare name, because
    /// nothing stops two files in that tree sharing one.
    @Test func aLoopOrASceneCanBeHeldJustAsAGeneratedClipCan() {
        var favorites = Favorites()

        let heldLoop = favorites.insert(path: "genau/clips/loop-two.mp4")
        let heldScene = favorites.insert(path: "non_AI/bucket/inner/scene-three.mkv")
        #expect(heldLoop)
        #expect(heldScene)

        #expect(favorites.held == ["genau/clips/loop-two", "non_AI/bucket/inner/scene-three"])
        #expect(favorites.contains(path: "genau/clips/loop-two.mp4"))
        #expect(favorites.contains(path: "non_AI/bucket/inner/scene-three.mkv"))

        let dropped = favorites.remove(path: "genau/clips/loop-two.mp4")
        #expect(dropped)
        #expect(!favorites.contains(path: "genau/clips/loop-two.mp4"))
        // A path naming no file names no clip.
        let nothing = favorites.insert(path: "genau/clips/")
        #expect(!nothing)
    }
}

/// The desktop writes `favs.csv` for Excel: CRLF rows of two quoted cells, each
/// an `=HYPERLINK` formula whose inner quotes are doubled. Every fixture path
/// below is invented; the shape is what matters.
@Suite struct FavsCSVTests {
    static let header = "local_file,web_url"
    static let firstRow = #""=HYPERLINK(""file:///C:/lib/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.mp4"";""C:\lib\2_outbox\upscaled_by_orientation\portrait\alpha\clip-one_topaz.mp4"")","=HYPERLINK(""https://example.test/gallery/clip-one"";""https://example.test/gallery/clip-one"")""#
    static let secondRow = #""=HYPERLINK(""file:///C:/lib/2_outbox/upscaled_by_orientation/landscape/beta/clip-two_topaz.mp4"";""C:\lib\2_outbox\upscaled_by_orientation\landscape\beta\clip-two_topaz.mp4"")",""""#

    @Test func readsTheStemOutOfTheDisplayArgumentOfEveryHyperlinkRow() {
        // The second argument is the plain Windows path, which round-trips
        // exactly; the first is percent-encoded as a file:// URI.
        let text = [Self.header, Self.firstRow, Self.secondRow].joined(separator: "\r\n") + "\r\n"
        #expect(FavsCSV.keys(in: text) == ["clip-one", "clip-two"])
    }
}

extension FavsCSVTests {
    @Test func survivesTheByteOrderMarkAndTheLineEndingsAnEditorLeavesBehind() {
        // The file reaches the phone through pCloud and whatever touched it on
        // the way; a BOM in front of the first row must not eat that row.
        let text = "\u{FEFF}" + [Self.firstRow, Self.secondRow].joined(separator: "\n")
        #expect(FavsCSV.keys(in: text) == ["clip-one", "clip-two"])
    }
}

extension FavsCSVTests {
    /// The file names whichever video Fun Time plays, so it holds rows for all
    /// three lanes — but only the upscale rows can be turned into a key here,
    /// because the other two lanes are filed under a library-relative path a
    /// Windows absolute path cannot be reduced to. The trap is that a delivered
    /// genau loop keeps the upscale's own name, `_topaz` and all
    /// (`evolver/tasks/genau_deliver.py`), so stripping the suffix on the
    /// strength of the name alone would file it under a clip that is not it.
    @Test func readsOnlyTheUpscaleRowsAndNotAGenauLoopThatMerelyLooksLikeOne() {
        let loop = #""=HYPERLINK(""file:///D:/lib/videos/genau/clips/loop-two_topaz.mp4"";""D:\lib\videos\genau\clips\loop-two_topaz.mp4"")",""""#
        let scene = #""=HYPERLINK(""file:///D:/lib/videos/2D/non_AI/bucket/scene-three.mkv"";""D:\lib\videos\2D\non_AI\bucket\scene-three.mkv"")",""""#

        let keys = FavsCSV.keys(in: [Self.header, Self.firstRow, loop, scene].joined(separator: "\r\n"))

        #expect(keys == ["clip-one"])
    }
}

extension FavsCSVTests {
    @Test func namesNothingFromAFileWithNoRowsThatParse() {
        #expect(FavsCSV.keys(in: "").isEmpty)
        #expect(FavsCSV.keys(in: Self.header + "\r\n").isEmpty)
        // A row whose formula is truncated names nothing.
        let torn = #""=HYPERLINK(""file:///C:/lib/clip-three_topaz.mp4"";""C:\lib\clip-three_topaz.mp4"#
        #expect(FavsCSV.keys(in: [Self.header, torn].joined(separator: "\r\n")).isEmpty)
    }
}

extension FavoritesTests {
    @Test func adoptingTheDesktopsRecordAddsToTheStoreRatherThanReplacingIt() {
        // The desktop's record — a favs.csv dropped in, or the flag on the
        // sidecars — is a snapshot from before the trip, not the truth: what was
        // favorited on the phone since must survive it.
        var favorites = Favorites(held: ["clip-one"])
        favorites.adopt(flagged: ["clip-one", "clip-two"])
        #expect(favorites.held == ["clip-one", "clip-two"])
    }
}

extension FavoritesTests {
    /// The hole a plain union leaves: the desktop's snapshot is read again on
    /// every launch, so an unfavorite made away from home would be undone by
    /// the next one — and the weird gesture's two-step demotion could never
    /// reach its second step, because the first step keeps being re-taken.
    @Test func aStemLetGoOnThePhoneIsNotHandedBackByAStaleSnapshot() {
        var favorites = Favorites(held: ["clip-one", "clip-two"])

        let dropped = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(dropped)
        favorites.adopt(flagged: ["clip-one", "clip-two"])
        #expect(favorites.held == ["clip-two"])

        // Two launches, three, a hundred: the answer does not drift.
        favorites.adopt(flagged: ["clip-one", "clip-two"])
        #expect(favorites.held == ["clip-two"])
    }
}

extension FavoritesTests {
    /// The hold is released the moment the desktop agrees — its record no
    /// longer names the clip, so the round trip is complete and the phone stops
    /// carrying the refusal. And a clip held again on the phone is held, full
    /// stop: the refusal it once made says nothing about the choice it just did.
    @Test func theRefusalIsDroppedOnceTheDesktopAgreesOrThePhoneChangesItsMind() {
        var favorites = Favorites(held: ["clip-one"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")

        favorites.adopt(flagged: ["clip-two"])          // the desktop caught up
        #expect(favorites.held == ["clip-two"])
        favorites.adopt(flagged: ["clip-one", "clip-two"])  // and later re-favorited it
        #expect(favorites.held == ["clip-one", "clip-two"])

        var again = Favorites(held: ["clip-one"])
        _ = again.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")
        let heldAgain = again.insert(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(heldAgain)
        again.adopt(flagged: ["clip-one"])
        #expect(again.held == ["clip-one"])
    }
}

extension FavoritesTests {
    /// The refusals outlive the app run, or a relaunch is exactly the moment
    /// the snapshot wins. A blob written before they existed still decodes.
    @Test func theRefusalsSurviveAJSONRoundTripAndAnOlderBlobStillDecodes() throws {
        var favorites = Favorites(held: ["clip-one", "clip-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")

        let data = try JSONEncoder().encode(favorites)
        var read = try JSONDecoder().decode(Favorites.self, from: data)
        read.adopt(flagged: ["clip-one", "clip-two"])
        #expect(read.held == ["clip-two"])

        // Written before the refusals existed, and under the old field name.
        let old = try JSONDecoder().decode(Favorites.self, from: Data(#"{"stems":["clip-one"]}"#.utf8))
        #expect(old.held == ["clip-one"])
    }
}

extension FavoritesTests {
    @Test func saysWhenNothingChangedSoTheJournalRecordsOnlyRealTurns() {
        // Locking a clip that is already a favorite is not a second favorite.
        var favorites = Favorites(held: ["clip-one"])
        let again = favorites.insert(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(!again)
        #expect(favorites.held == ["clip-one"])

        let removed = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(removed)
        #expect(favorites.held.isEmpty)
        let removedTwice = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(!removedTwice)
    }
}

extension FavsCSVTests {
    @Test func anEmptyLeadingCellNeverReadsAStemOutOfTheWrongColumn() {
        // Splitting away empty subsequences would hand the second column to the
        // first-cell parser — a stem must come from local_file or not at all.
        #expect(FavsCSV.keys(in: ",=HYPERLINK(\"x\";\"C:\\\\l\\\\k_topaz.mp4\")") == [])
    }

    @Test func aLeadingSpaceBeforeTheFormulaStillParses() {
        // The desktop reads rows through csv.DictReader, which strips nothing —
        // but hand-edited rows arrive with stray spaces, and the stem is the same.
        let row = " =HYPERLINK(\"file:///C:/lib/x_topaz.mp4\";\"C:\\\\lib\\\\x_topaz.mp4\")"
        #expect(FavsCSV.keys(in: row) == ["x"])
    }
}

extension FavoritesTests {
    /// A record that could not speak for a lane is not the desktop agreeing.
    /// The corpus is fetched branch by branch and a branch that fails to answer
    /// is skipped, so absence from THAT record means the lane was missing —
    /// reading it as agreement would hand a dropped favorite straight back.
    @Test func aRefusalOutsideWhatTheRecordCoveredIsKept() {
        var favorites = Favorites(held: ["clip-one", "genau/clips/loop-two"])
        _ = favorites.remove(path: "1_sorted/alpha/portrait/clip-one.mp4")
        _ = favorites.remove(path: "genau/clips/loop-two.mp4")

        // Only the genau branch answered this time.
        favorites.adopt(flagged: [], covering: ["genau/clips/loop-two"])

        // The loop's refusal is settled; the clip's is still owed an answer.
        favorites.adopt(flagged: ["clip-one", "genau/clips/loop-two"],
                        covering: ["clip-one", "genau/clips/loop-two"])
        #expect(favorites.held == ["genau/clips/loop-two"])
    }
}
