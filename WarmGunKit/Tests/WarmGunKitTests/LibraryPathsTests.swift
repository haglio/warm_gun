import Testing
@testable import WarmGunKit

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

extension LibraryPathsTests {
    @Test func namesTheFolderTheWeirdGestureMovesAnUpscaleInto() {
        #expect(LibraryPaths.weirdDir == "2_outbox/kinda_weird")
    }
}

extension LibraryPathsTests {
    private static func folder(_ name: String, _ contents: [PCloudEntry] = []) -> PCloudEntry {
        PCloudEntry(name: name, isfolder: true, contents: contents)
    }

    @Test func findsTheLibraryByItsSkeletonWithoutBeingToldWhereItLives() {
        // The library is the one folder holding both pipeline stages. Its real
        // path names are private and live only in the account, never in code —
        // discovery is what makes the path a non-setting.
        let root = Self.folder("/", [
            Self.folder("alpha", [
                Self.folder("videos", [
                    Self.folder("videos", [
                        Self.folder("2D", [
                            Self.folder("AI", [Self.folder("1_sorted"), Self.folder("2_outbox")]),
                        ]),
                    ]),
                    // The metadata mirror carries 2_outbox alone — no original
                    // stage, not the library.
                    Self.folder("metadata", [Self.folder("2D", [Self.folder("AI", [Self.folder("2_outbox")])])]),
                ]),
            ]),
        ])
        #expect(LibraryPaths.discoverLibrary(root: root) == "/alpha/videos/videos/2D/AI")
    }

    @Test func aSubtreeListingYieldsAbsolutePathsWhenGivenItsBase() {
        // When the root refuses a recursive listing, discovery descends and
        // lists subtrees — whose candidates must still come back as full
        // account paths, not paths relative to wherever the walk stood.
        let subtree = Self.folder("videos", [
            Self.folder("2D", [Self.folder("AI", [Self.folder("1_sorted"), Self.folder("2_outbox")])]),
        ])
        #expect(LibraryPaths.discoverLibrary(root: subtree, at: "/alpha/videos") == "/alpha/videos/2D/AI")
    }

    @Test func anArchivedCopyLosesToTheLiveTree() {
        // Parked trees ride under underscore-prefixed folders by convention;
        // ties break on depth, then on the path itself, so the answer is one
        // value however the listing is ordered.
        let live = Self.folder("lib", [Self.folder("1_sorted"), Self.folder("2_outbox")])
        let parked = Self.folder("_old", [Self.folder("lib", [Self.folder("1_sorted"), Self.folder("2_outbox")])])
        let root = Self.folder("/", [parked, live])
        #expect(LibraryPaths.discoverLibrary(root: root) == "/lib")
        #expect(LibraryPaths.discoverLibrary(root: Self.folder("/", [Self.folder("empty")])) == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheGenauClipsFolderBesideTheLibrary() {
        // Evolver delivers genau loops OUT of the pipeline into
        // videos/genau/clips — a sibling of the videos/videos tree the library
        // path points into, reachable from it by construction.
        #expect(LibraryPaths.genauClipsPath(forLibrary: "/alpha/videos/videos/2D/AI")
                == "/alpha/videos/genau/clips")
        #expect(LibraryPaths.genauClipsPath(forLibrary: "/AI") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheNonAITreeBesideTheLibrary() {
        // "Full length" in Fun Time's sense IS the non-AI library — the real
        // scenes under 2D/non_AI, the AI folder's sibling.
        #expect(LibraryPaths.nonAIPath(forLibrary: "/alpha/videos/videos/2D/AI")
                == "/alpha/videos/videos/2D/non_AI")
        #expect(LibraryPaths.nonAIPath(forLibrary: "/") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheMetadataMirrorAndMapsASidecarBackToItsOriginal() {
        // The sidecars mirror the UPSCALE tree under videos/metadata (the
        // videos tree's sibling): a zip of its 2D/AI branch holds entries like
        // 2D/AI/2_outbox/upscaled_by_orientation/<orientation>/<source>/<stem>_topaz.json,
        // each speaking for the original at 1_sorted/<source>/<orientation>/<stem>.mp4.
        #expect(LibraryPaths.metadataAIPath(forLibrary: "/alpha/videos/videos/2D/AI")
                == "/alpha/videos/metadata/2D/AI")
        #expect(LibraryPaths.metadataAIPath(forLibrary: "/x") == nil)
        // The zip's root depends on what the server chose to zip, so the
        // parser anchors on the spine, not on a fixed prefix.
        #expect(LibraryPaths.originalPath(forSidecarEntry: "2D/AI/2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json")
                == "1_sorted/alpha/portrait/clip-one.mp4")
        #expect(LibraryPaths.originalPath(forSidecarEntry: "2_outbox/upscaled_by_orientation/landscape/beta/clip-two_topaz.json")
                == "1_sorted/beta/landscape/clip-two.mp4")
        #expect(LibraryPaths.originalPath(forSidecarEntry: "2D/non_AI/beta/scene.json") == nil)
        #expect(LibraryPaths.originalPath(forSidecarEntry: "2D/AI/2_outbox/upscaled_by_orientation/portrait/alpha/odd-name.json") == nil)
    }
}

extension LibraryPathsTests {
    @Test func readsTheFilenameOutOfACatalogPath() {
        #expect(LibraryPaths.filename(ofClip: "1_sorted/alpha/portrait/clip-one.mp4") == "clip-one.mp4")
        #expect(LibraryPaths.filename(ofClip: "non_AI/beta/a scene.mkv") == "a scene.mkv")
        #expect(LibraryPaths.filename(ofClip: "bare.mp4") == "bare.mp4")
        #expect(LibraryPaths.filename(ofClip: "genau/clips/") == nil)
        #expect(LibraryPaths.filename(ofClip: "") == nil)
    }
}
