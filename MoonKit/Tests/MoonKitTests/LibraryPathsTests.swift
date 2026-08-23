import Testing
@testable import MoonKit

@Suite struct LibraryPathsTests {
    @Test func parsesAnOriginalPathIntoSourceOrientationAndStem() {
        let parsed = LibraryPaths.parseOriginal("1_sorted/alpha/portrait/clip-one.mp4")
        #expect(parsed?.source == "alpha")
        #expect(parsed?.orientation == .portrait)
        #expect(parsed?.stem == "clip-one")
    }
}

extension LibraryPathsTests {
    @Test func refusesPathsOutsideTheSortedTree() {
        #expect(LibraryPaths.parseOriginal("2_outbox/upscaled_by_orientation/portrait/alpha/clip_topaz.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/sideways/clip.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait/noext") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheUpscaleOfAnOriginalWithTheTreesNestedTheOtherWayRound() {
        #expect(LibraryPaths.upscalePath(forOriginal: "1_sorted/alpha/portrait/clip-one.mp4")
                == "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.mp4")
        #expect(LibraryPaths.upscalePath(forOriginal: "not/a/library/path.mp4") == nil)
    }
}

extension LibraryPathsTests {
    @Test func readsTheStemOutOfADesktopUpscaleReferenceWhateverTheSeparators() {
        #expect(LibraryPaths.stem(ofUpscaleReference: #"C:\lib\2_outbox\upscaled_by_orientation\portrait\alpha\clip-one_topaz.mp4"#) == "clip-one")
        #expect(LibraryPaths.stem(ofUpscaleReference: "/lib/2_outbox/upscaled_by_orientation/landscape/beta/a_b_c_topaz.mp4") == "a_b_c")
        #expect(LibraryPaths.stem(ofUpscaleReference: "/lib/1_sorted/beta/landscape/a_b_c.mp4") == nil)
    }
}
