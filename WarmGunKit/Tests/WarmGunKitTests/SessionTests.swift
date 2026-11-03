import Testing
@testable import WarmGunKit

@Suite struct SessionTests {
    static let three = ["1_sorted/alpha/portrait/video-one.mp4",
                        "1_sorted/alpha/portrait/video-two.mp4",
                        "1_sorted/beta/landscape/video-three.mp4"]

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
        #expect(session.index == 0)
        session.step(-1)
        #expect(session.index == 2)
    }
}

extension SessionTests {
    @Test func advanceRollsOntoTheStagedVideoAndWrapsAtTheEnd() {
        var session = Session(playlist: Self.three, index: 2)
        #expect(session.staged == Self.three[0])
        session.advance()
        #expect(session.index == 0)
        session.advance()
        #expect(session.current == Self.three[1])
    }
}

extension SessionTests {
    @Test func lockHoldsTheVideoAndStagesNothingUntilItIsReleased() {
        var session = Session(playlist: Self.three)
        session.setLocked(true)
        #expect(session.locked)
        #expect(session.staged == nil)
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
    @Test func playingAVideoIntoAnEmptySessionStartsTheRunWithIt() {
        var session = Session(playlist: [])
        session.playFile(Self.three[0])
        #expect(session.playlist == [Self.three[0]])
        #expect(session.index == 0)
        #expect(session.current == Self.three[0])
    }
}

extension SessionTests {
    @Test func playingANewcomerSplicesItInAfterTheCurrentVideoAndPlaysIt() {
        var session = Session(playlist: Self.three)
        let newcomer = "1_sorted/gamma/portrait/video-four.mp4"
        session.playFile(newcomer)
        #expect(session.index == 1)
        #expect(session.current == newcomer)
        #expect(session.playlist == [Self.three[0], newcomer, Self.three[1], Self.three[2]])
    }
}

extension SessionTests {
    @Test func playingAVideoAlreadyInTheListJumpsToItWithoutGrowingIt() {
        var session = Session(playlist: Self.three)
        session.playFile(Self.three[2])
        #expect(session.index == 2)
        #expect(session.current == Self.three[2])
        #expect(session.playlist == Self.three)
    }
}

extension SessionTests {
    @Test func replacingThePlaylistRestartsAtTheTopWhenTheVideoIsGone() {
        var session = Session(playlist: Self.three, index: 1)
        let rebuilt = ["1_sorted/gamma/portrait/video-four.mp4",
                       "1_sorted/gamma/landscape/video-five.mp4"]
        session.replacePlaylist(rebuilt)
        #expect(session.index == 0)
        #expect(session.current == rebuilt[0])
        #expect(session.playlist == rebuilt)
    }
}

extension SessionTests {
    @Test func replacingThePlaylistKeepsTheVideoOnScreenWhenItSurvives() {
        var session = Session(playlist: Self.three, index: 1)
        session.setLocked(true)
        session.replacePlaylist(["1_sorted/gamma/portrait/video-four.mp4",
                                 Self.three[1],
                                 "1_sorted/gamma/landscape/video-five.mp4"])
        #expect(session.current == Self.three[1])
        #expect(session.index == 1)
        #expect(session.locked)
    }
}

extension SessionTests {
    @Test func theOnlyRemainingEntryCannotBeDiscarded() {
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
        var session = Session(playlist: Self.three)
        session.setLocked(true)
        #expect(session.discard() == Self.three[0])
        #expect(session.locked == false)
        #expect(session.staged == Self.three[2])

        var lone = Session(playlist: [Self.three[0]])
        lone.setLocked(true)
        #expect(lone.discard() == nil)
        #expect(lone.locked == false)
    }
}

extension SessionTests {
    @Test func anEmptyReplacementLeavesTheRunInPlace() {
        var session = Session(playlist: Self.three, index: 1)
        session.replacePlaylist([])
        #expect(session.playlist == Self.three)
        #expect(session.current == Self.three[1])
    }
}

extension SessionTests {
    @Test func aRebuildThatLosesTheHeldVideoReleasesTheHold() {
        var session = Session(playlist: Self.three, index: 1)
        session.setLocked(true)
        session.replacePlaylist(["1_sorted/gamma/portrait/video-four.mp4",
                                 "1_sorted/gamma/landscape/video-five.mp4"])
        #expect(session.index == 0)
        #expect(session.locked == false)
    }
}

extension SessionTests {
    @Test func aResumedRunStartsOverWhenEmptyRebuildsWhenItsVideoNoLongerFitsAndElseStands() {
        #expect(Session(playlist: []).resumption(currentFits: true) == .startFromTop)
        #expect(Session(playlist: []).resumption(currentFits: false) == .startFromTop)
        #expect(Session(playlist: Self.three).resumption(currentFits: false) == .rebuildAroundCurrent)
        #expect(Session(playlist: Self.three).resumption(currentFits: true) == .keep)
    }
}

extension SessionTests {
    @Test func aRelaunchResumesTheSavedRunOnItsVideoLessWhatTheLibraryLost() {
        let known = Set([Self.three[0], Self.three[2]])
        let resumed = Session(restoring: Self.three, at: 2, locked: true, keeping: known)
        #expect(resumed.playlist == [Self.three[0], Self.three[2]])
        #expect(resumed.current == Self.three[2])
        #expect(resumed.locked)

        let lost = Session(restoring: Self.three, at: 1, locked: true, keeping: known)
        #expect(lost.current == Self.three[0])
        #expect(!lost.locked)

        let pastTheEnd = Session(restoring: Self.three, at: 7, locked: false, keeping: Set(Self.three))
        #expect(pastTheEnd.current == Self.three[0])
    }
}
