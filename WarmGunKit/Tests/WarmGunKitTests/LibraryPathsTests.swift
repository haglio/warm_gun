import Testing
@testable import WarmGunKit

@Suite struct LibraryPathsTests {
    @Test func parsesAnOriginalPathIntoSourceShapeAndStem() {
        let parsed = LibraryPaths.parseOriginal("1_sorted/alpha/portrait/video-one.mp4")
        #expect(parsed?.source == "alpha")
        #expect(parsed?.shape == .portrait)
        #expect(parsed?.stem == "video-one")
    }
}

extension LibraryPathsTests {
    @Test func refusesPathsOutsideTheSortedTree() {
        #expect(LibraryPaths.parseOriginal("2_outbox/upscaled_by_orientation/portrait/alpha/video_topaz.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/sideways/video.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait/noext") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheUpscaleOfAnOriginalWithTheTreesNestedTheOtherWayRound() {
        #expect(LibraryPaths.upscalePath(forOriginal: "1_sorted/alpha/portrait/video-one.mp4")
                == "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz.mp4")
        #expect(LibraryPaths.upscalePath(forOriginal: "not/a/library/path.mp4") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheFolderTheTrashGestureMovesAnUpscaleInto() {
        #expect(LibraryPaths.trashDir == "2_outbox/trash")
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
    @Test func namesGenausFolderBesideTheLibrarysTwoDFolder() {
        #expect(LibraryPaths.genauPath(forLibrary: "/alpha/videos/videos/2D/AI") == "/alpha/videos/videos/genau")
        #expect(LibraryPaths.genauPath(forLibrary: "/2D/AI") == nil)
        #expect(LibraryPaths.genauPath(forLibrary: "/AI") == nil)
    }

    @Test func findsGenausFlicksByTheShapeOfTheirFolderWhateverItIsCalled() {
        func genau(holdingFlicksIn name: String) -> PCloudEntry {
            Self.folder("genau", [
                Self.folder("audio"),
                Self.folder(name, [Self.folder("2D", [Self.folder("AI"), Self.folder("non_AI")]), Self.folder("VR")]),
                Self.folder("trash", [Self.folder("2D"), Self.folder("VR")]),
            ])
        }

        #expect(LibraryPaths.genauFlicksFolder(in: genau(holdingFlicksIn: "videos")) == "videos")
        #expect(LibraryPaths.genauFlicksFolder(in: genau(holdingFlicksIn: "flicks")) == "flicks")
    }

    @Test func findsNoGenauFlicksWhereNoFolderOrMoreThanOneHasTheirShape() {
        let none = Self.folder("genau", [Self.folder("audio"), Self.folder("trash", [Self.folder("2D")])])
        let two = Self.folder("genau", [Self.folder("alpha", [Self.folder("2D")]),
                                        Self.folder("beta", [Self.folder("2D")])])

        #expect(LibraryPaths.genauFlicksFolder(in: none) == nil)
        #expect(LibraryPaths.genauFlicksFolder(in: two) == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheNonAITreeBesideTheLibrary() {
        #expect(LibraryPaths.nonAIPath(forLibrary: "/alpha/videos/videos/2D/AI")
                == "/alpha/videos/videos/2D/non_AI")
        #expect(LibraryPaths.nonAIPath(forLibrary: "/") == nil)
    }
}

extension LibraryPathsTests {
    @Test func readsTheFilenameOutOfACatalogPath() {
        #expect(LibraryPaths.filename(ofVideo: "1_sorted/alpha/portrait/video-one.mp4") == "video-one.mp4")
        #expect(LibraryPaths.filename(ofVideo: "non_AI/beta/a scene.mkv") == "a scene.mkv")
        #expect(LibraryPaths.filename(ofVideo: "bare.mp4") == "bare.mp4")
        #expect(LibraryPaths.filename(ofVideo: "genau/clips/") == nil)
        #expect(LibraryPaths.filename(ofVideo: "") == nil)
    }
}

extension LibraryPathsTests {
    /// Every lane the phone plays from has a sidecar, and the three of them are
    /// filed differently: an AI original is spoken for by its UPSCALE's sidecar
    /// (source and shape the other way round), while a Genau flick and a
    /// real scene mirror straight across. The extension is dropped either way,
    /// so a scene that is not an .mp4 still finds its file.
    @Test func eachLaneKnowsWhichBranchHoldsItsSidecarAndWhereInIt() {
        let ai = LibraryPaths.MetadataBranch.ai
        let genau = LibraryPaths.MetadataBranch.genau
        let nonAI = LibraryPaths.MetadataBranch.nonAI

        #expect(ai.sidecarPath(forVideo: "1_sorted/alpha/portrait/video-one.mp4")
                == "2_outbox/upscaled_by_orientation/portrait/alpha/video-one_topaz")
        #expect(genau.sidecarPath(forVideo: "genau/clips/2D/AI/loop-two.mp4") == "2D/AI/loop-two")
        #expect(nonAI.sidecarPath(forVideo: "non_AI/bucket/inner/scene-three.mkv")
                == "bucket/inner/scene-three")

        // A branch answers for its own lane and no other.
        #expect(ai.sidecarPath(forVideo: "genau/clips/2D/AI/loop-two.mp4") == nil)
        #expect(genau.sidecarPath(forVideo: "non_AI/bucket/scene.mp4") == nil)
        #expect(nonAI.sidecarPath(forVideo: "1_sorted/alpha/portrait/video-one.mp4") == nil)
        #expect(nonAI.sidecarPath(forVideo: "non_AI/scene.mp4") == "scene")
    }
}

extension LibraryPathsTests {
    /// What the phone remembers by name -- the videos sent to Trash, the
    /// favorites -- outlives the split of Genau's flicks folder into 2D and VR:
    /// a name from before it is carried to the one flick with that file name.
    @Test func aNameFromBeforeGenausFolderSplitIsCarriedToWhereTheVideoIsNow() {
        let now: Set<String> = ["genau/clips/2D/AI/loop-one.mp4", "genau/clips/2D/AI/twin.mp4",
                                "genau/clips/2D/non_AI/twin.mp4"]

        let carried = LibraryPaths.rekeyedFlatGenau(
            ["genau/clips/loop-one.mp4", "genau/clips/twin.mp4", "genau/clips/gone.mp4",
             "1_sorted/alpha/portrait/video-one.mp4"],
            against: now)

        #expect(carried == ["genau/clips/2D/AI/loop-one.mp4", "genau/clips/twin.mp4",
                            "genau/clips/gone.mp4", "1_sorted/alpha/portrait/video-one.mp4"])
    }
}

extension LibraryPathsTests {
    /// The mirror parallels the video tree: `videos/metadata` beside
    /// `videos/videos`, and Genau's folder sits beside `2D` in both — which is
    /// why its branch is not under `2D` like the other two.
    @Test func theThreeMetadataBranchesSitBesideTheVideoTree() {
        let library = "/alpha/videos/videos/2D/AI"

        #expect(LibraryPaths.MetadataBranch.ai.path(forLibrary: library, genauFlicksFolder: "flicks")
                == "/alpha/videos/metadata/2D/AI")
        #expect(LibraryPaths.MetadataBranch.genau.path(forLibrary: library, genauFlicksFolder: "flicks")
                == "/alpha/videos/metadata/genau/flicks")
        #expect(LibraryPaths.MetadataBranch.nonAI.path(forLibrary: library, genauFlicksFolder: "flicks")
                == "/alpha/videos/metadata/2D/non_AI")
        #expect(LibraryPaths.MetadataBranch.allCases.count == 3)
        #expect(LibraryPaths.MetadataBranch.ai.path(forLibrary: "/x", genauFlicksFolder: "flicks") == nil)
    }

    @Test func genausMetadataBranchIsNowhereUntilItsFlicksFolderIsFound() {
        let library = "/alpha/videos/videos/2D/AI"

        #expect(LibraryPaths.MetadataBranch.genau.path(forLibrary: library, genauFlicksFolder: nil) == nil)
        #expect(LibraryPaths.MetadataBranch.ai.path(forLibrary: library, genauFlicksFolder: nil)
                == "/alpha/videos/metadata/2D/AI")
    }
}

extension LibraryPathsTests {
    /// What a favorite is filed under. A generated video's stem is unique
    /// library-wide because `1_sorted` and `2_outbox` are in total
    /// correspondence, and it has to stay the key because the desktop's
    /// favorites file knows that name and nothing else. Nothing makes the same
    /// promise for the other two lanes — the non-AI tree is walked recursively
    /// on both sides and the genau folder holds videos carved by hand as well as
    /// generated ones — so those are filed under their whole path, where the
    /// library itself already guarantees uniqueness.
    @Test func aFavoriteIsFiledUnderAStemInTheAILaneAndAWholePathInTheOthers() {
        #expect(LibraryPaths.favoriteKey(forVideo: "1_sorted/alpha/portrait/video-one.mp4") == "video-one")
        #expect(LibraryPaths.favoriteKey(forVideo: "genau/clips/2D/AI/loop-two_topaz.mp4") == "genau/clips/2D/AI/loop-two_topaz")
        #expect(LibraryPaths.favoriteKey(forVideo: "non_AI/bucket/inner/scene-three.mkv")
                == "non_AI/bucket/inner/scene-three")
        // Two same-named scenes in different folders are two videos, not one.
        #expect(LibraryPaths.favoriteKey(forVideo: "non_AI/one/scene.mp4")
                != LibraryPaths.favoriteKey(forVideo: "non_AI/two/scene.mp4"))
        #expect(LibraryPaths.favoriteKey(forVideo: "genau/clips/") == nil)
        #expect(LibraryPaths.favoriteKey(forVideo: "somewhere/else/thing.mp4") == nil)
    }
}

extension LibraryPathsTests {
    @Test func droppingAnExtensionLeavesTheStemAndNeedsAStemAndAnExtension() {
        #expect(LibraryPaths.dropExtension("non_AI/beta/scene.mkv") == "non_AI/beta/scene")
        #expect(LibraryPaths.dropExtension("non_AI/beta/scene") == nil)
        #expect(LibraryPaths.dropExtension("non_AI/be.ta/scene") == nil)
        #expect(LibraryPaths.dropExtension("non_AI/beta/.mkv") == nil)
    }
}
