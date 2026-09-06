import Testing
@testable import WarmGunKit

@Suite struct SessionTests {
    static let three = ["1_sorted/alpha/portrait/clip-one.mp4",
                        "1_sorted/alpha/portrait/clip-two.mp4",
                        "1_sorted/beta/landscape/clip-three.mp4"]

    @Test func startsOnTheFirstEntryAndStagesTheOneAfterIt() {
        let session = Session(playlist: Self.three)
        #expect(session.index == 0)
        #expect(session.current == Self.three[0])
        #expect(session.staged == Self.three[1])
        #expect(session.locked == false)
    }
}

extension SessionTests {
    @Test func stepWrapsPastEitherEnd() {
        var session = Session(playlist: Self.three)
        session.step(1)
        #expect(session.index == 1)
        session.step(2)
        #expect(session.index == 0)  // wraps forward
        session.step(-1)
        #expect(session.index == 2)  // and backward
    }
}

extension SessionTests {
    @Test func advanceRollsOntoTheStagedClipAndWrapsAtTheEnd() {
        var session = Session(playlist: Self.three, index: 2)
        #expect(session.staged == Self.three[0])
        session.advance()
        #expect(session.index == 0)
        session.advance()
        #expect(session.current == Self.three[1])
    }
}

extension SessionTests {
    @Test func lockHoldsTheClipAndStagesNothingUntilItIsReleased() {
        var session = Session(playlist: Self.three)
        session.setLocked(true)
        #expect(session.locked)
        #expect(session.staged == nil)  // nothing may roll on off a locked clip
        session.advance()
        #expect(session.index == 0)

        session.setLocked(false)
        #expect(session.staged == Self.three[1])
        session.advance()
        #expect(session.index == 1)
    }
}

extension SessionTests {
    @Test func navigatingReleasesTheLock() {
        // The desktop's dispatcher sends UNLOCK before any NEXT/PREV: a deliberate
        // step off a held clip means you are done holding it.
        var session = Session(playlist: Self.three)
        session.setLocked(true)
        session.step(1)
        #expect(session.locked == false)
        #expect(session.staged == Self.three[2])
    }
}

extension SessionTests {
    @Test func discardDropsTheCurrentEntryAndTheNextShiftsIntoItsPlace() {
        var session = Session(playlist: Self.three)
        #expect(session.discard() == Self.three[0])
        #expect(session.playlist == [Self.three[1], Self.three[2]])
        #expect(session.index == 0)
        #expect(session.current == Self.three[1])
    }
}

extension SessionTests {
    @Test func playingAClipIntoAnEmptySessionStartsTheRunWithIt() {
        // The session before the first index arrives is empty, and a favorites
        // jump may land in it: it starts the run rather than reaching past its end.
        var session = Session(playlist: [])
        session.playFile(Self.three[0])
        #expect(session.playlist == [Self.three[0]])
        #expect(session.index == 0)
        #expect(session.current == Self.three[0])
    }
}

extension SessionTests {
    @Test func playingANewcomerSplicesItInAfterTheCurrentClipAndPlaysIt() {
        // What a favorites jump does with a clip the live filters exclude: it is
        // spliced next, so the run carries on into the list it came from.
        var session = Session(playlist: Self.three)
        let newcomer = "1_sorted/gamma/portrait/clip-four.mp4"
        session.playFile(newcomer)
        #expect(session.index == 1)
        #expect(session.current == newcomer)
        #expect(session.playlist == [Self.three[0], newcomer, Self.three[1], Self.three[2]])
    }
}

extension SessionTests {
    @Test func playingAClipAlreadyInTheListJumpsToItWithoutGrowingIt() {
        var session = Session(playlist: Self.three)
        session.playFile(Self.three[2])
        #expect(session.index == 2)
        #expect(session.current == Self.three[2])
        #expect(session.playlist == Self.three)
    }
}

extension SessionTests {
    @Test func replacingThePlaylistRestartsAtTheTopWhenTheClipIsGone() {
        var session = Session(playlist: Self.three, index: 1)
        let rebuilt = ["1_sorted/gamma/portrait/clip-four.mp4",
                       "1_sorted/gamma/landscape/clip-five.mp4"]
        session.replacePlaylist(rebuilt)
        #expect(session.index == 0)
        #expect(session.current == rebuilt[0])
        #expect(session.playlist == rebuilt)
    }
}

extension SessionTests {
    @Test func replacingThePlaylistKeepsTheClipOnScreenWhenItSurvives() {
        // A filter toggle rebuilds the list; the clip you are watching should
        // keep playing rather than flicker back to the top of the new one.
        var session = Session(playlist: Self.three, index: 1)
        session.setLocked(true)
        session.replacePlaylist(["1_sorted/gamma/portrait/clip-four.mp4",
                                 Self.three[1],
                                 "1_sorted/gamma/landscape/clip-five.mp4"])
        #expect(session.current == Self.three[1])
        #expect(session.index == 1)
        #expect(session.locked)  // a rebuild is not a gesture: the hold stands
    }
}

extension SessionTests {
    @Test func theOnlyRemainingEntryCannotBeDiscarded() {
        // A satellite must always have something to play, so the final clip is a
        // no-op rather than an empty screen.
        var session = Session(playlist: [Self.three[0]])
        #expect(session.discard() == nil)
        #expect(session.playlist == [Self.three[0]])

        var empty = Session(playlist: [])
        #expect(empty.discard() == nil)
    }
}

extension SessionTests {
    @Test func discardingTheLastEntryWrapsToTheTop() {
        var session = Session(playlist: Self.three, index: 2)
        #expect(session.discard() == Self.three[2])
        #expect(session.index == 0)
        #expect(session.current == Self.three[0])
    }
}

extension SessionTests {
    @Test func aRestoredIndexBeyondTheListIsWrappedRatherThanTrusted() {
        // The saved position is restored onto a rebuilt playlist, which may have
        // shrunk since — the desktop wraps on load (`session.py`), never traps.
        let session = Session(playlist: Self.three, index: 7)
        #expect(session.index == 1)
        #expect(session.current == Self.three[1])

        let empty = Session(playlist: [], index: 3)
        #expect(empty.index == 0)
        #expect(empty.current == nil)
    }
}

extension SessionTests {
    @Test func discardReleasesTheLockSoTheRunCarriesOn() {
        // The desktop dispatcher sends UNLOCK before TRASH for the same reason it
        // does before NEXT (`command_dispatch.py`): a locked satellite is
        // repeat-one, and without the release the clip that shifts into the
        // discarded slot would be held forever with nothing staged behind it.
        var session = Session(playlist: Self.three)
        session.setLocked(true)
        #expect(session.discard() == Self.three[0])
        #expect(session.locked == false)
        #expect(session.staged == Self.three[2])

        var lone = Session(playlist: [Self.three[0]])
        lone.setLocked(true)
        #expect(lone.discard() == nil)
        #expect(lone.locked == false)  // the no-op discard still releases
    }
}

extension SessionTests {
    @Test func anEmptyReplacementLeavesTheRunInPlace() {
        // A filter that matches nothing must not blank the screen: the desktop
        // refuses an empty replacement outright (`session.py` raises), and the
        // design says the current playlist stays until a filter matches again.
        var session = Session(playlist: Self.three, index: 1)
        session.replacePlaylist([])
        #expect(session.playlist == Self.three)
        #expect(session.current == Self.three[1])
    }
}

extension SessionTests {
    @Test func aRebuildThatLosesTheHeldClipReleasesTheHold() {
        // The desktop cancels the lock on every rebuild that touches the player
        // (`command_dispatch.py` `_cancel_lock`): repeat-one must never be
        // inherited by whatever clip happens to land at the top of a new list.
        var session = Session(playlist: Self.three, index: 1)
        session.setLocked(true)
        session.replacePlaylist(["1_sorted/gamma/portrait/clip-four.mp4",
                                 "1_sorted/gamma/landscape/clip-five.mp4"])
        #expect(session.index == 0)
        #expect(session.locked == false)
    }
}
