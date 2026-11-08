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
        #expect(LibraryPaths.parseOriginal("2D/AI/portrait/alpha/video_topaz.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/sideways/video.mp4") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait/noext") == nil)
        #expect(LibraryPaths.parseOriginal("1_sorted/alpha/portrait") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesTheUpscaleOfAnOriginalWithTheTreesNestedTheOtherWayRound() {
        #expect(LibraryPaths.upscalePath(forOriginal: "1_sorted/alpha/portrait/video-one.mp4")
                == "2D/AI/portrait/alpha/video-one_topaz.mp4")
        #expect(LibraryPaths.upscalePath(forOriginal: "not/a/library/path.mp4") == nil)
    }
}

extension LibraryPathsTests {
    @Test func namesKinosFolderBesideTheLibrarysTwoDFolderAsGenausIs() {
        #expect(LibraryPaths.kinoPath(forLibrary: "/alpha/videos/videos/2D/AI") == "/alpha/videos/videos/kino")
        #expect(LibraryPaths.kinoPath(forLibrary: "/AI") == nil)
    }

    @Test func namesTheFolderInKinosTheTrashGestureMovesAnUpscaleInto() {
        #expect(LibraryPaths.kinoTrashFolder == "trash")
    }
}

extension LibraryPathsTests {
    private static func folder(_ name: String, _ contents: [PCloudEntry] = []) -> PCloudEntry {
        PCloudEntry(name: name, isfolder: true, contents: contents)
    }

    @Test func findsTheLibraryByItsSkeletonWithoutBeingToldWhereItLives() {
        let root = Self.folder("/", [
            Self.folder("alpha", [
                Self.folder("videos", [
                    Self.folder("videos", [
                        Self.folder("2D", [
                            Self.folder("AI", [Self.folder("0_inbox"), Self.folder("1_sorted")]),
                        ]),
                    ]),
                    Self.folder("metadata", [Self.folder("2D", [Self.folder("AI", [Self.folder("1_sorted")])])]),
                ]),
            ]),
        ])
        #expect(LibraryPaths.discoverLibrary(root: root) == "/alpha/videos/videos/2D/AI")
    }

    @Test func aSubtreeListingYieldsAbsolutePathsWhenGivenItsBase() {
        let subtree = Self.folder("videos", [
            Self.folder("2D", [Self.folder("AI", [Self.folder("0_inbox"), Self.folder("1_sorted")])]),
        ])
        #expect(LibraryPaths.discoverLibrary(root: subtree, at: "/alpha/videos") == "/alpha/videos/2D/AI")
    }

    @Test func anArchivedCopyLosesToTheLiveTree() {
        let live = Self.folder("lib", [Self.folder("0_inbox"), Self.folder("1_sorted")])
        let parked = Self.folder("_old", [Self.folder("lib", [Self.folder("0_inbox"), Self.folder("1_sorted")])])
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
    @Test func eachLaneKnowsWhichBranchHoldsItsSidecarAndWhereInIt() {
        let ai = LibraryPaths.MetadataBranch.ai
        let genau = LibraryPaths.MetadataBranch.genau
        let nonAI = LibraryPaths.MetadataBranch.nonAI

        #expect(ai.sidecarPath(forVideo: "1_sorted/alpha/portrait/video-one.mp4")
                == "portrait/alpha/video-one_topaz")
        #expect(genau.sidecarPath(forVideo: "genau/clips/2D/AI/loop-two.mp4") == "2D/AI/loop-two")
        #expect(nonAI.sidecarPath(forVideo: "non_AI/bucket/inner/scene-three.mkv")
                == "bucket/inner/scene-three")

        #expect(ai.sidecarPath(forVideo: "genau/clips/2D/AI/loop-two.mp4") == nil)
        #expect(genau.sidecarPath(forVideo: "non_AI/bucket/scene.mp4") == nil)
        #expect(nonAI.sidecarPath(forVideo: "1_sorted/alpha/portrait/video-one.mp4") == nil)
        #expect(nonAI.sidecarPath(forVideo: "non_AI/scene.mp4") == "scene")
    }
}

extension LibraryPathsTests {
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
    @Test func theThreeMetadataBranchesSitBesideTheVideoTree() {
        let library = "/alpha/videos/videos/2D/AI"

        #expect(LibraryPaths.MetadataBranch.ai.path(forLibrary: library, genauFlicksFolder: "flicks")
                == "/alpha/videos/metadata/kino/2D/AI")
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
                == "/alpha/videos/metadata/kino/2D/AI")
    }
}

extension LibraryPathsTests {
    @Test func aFavoriteIsFiledUnderAStemInTheAILaneAndAWholePathInTheOthers() {
        #expect(LibraryPaths.favoriteKey(forVideo: "1_sorted/alpha/portrait/video-one.mp4") == "video-one")
        #expect(LibraryPaths.favoriteKey(forVideo: "genau/clips/2D/AI/loop-two_topaz.mp4") == "genau/clips/2D/AI/loop-two_topaz")
        #expect(LibraryPaths.favoriteKey(forVideo: "non_AI/bucket/inner/scene-three.mkv")
                == "non_AI/bucket/inner/scene-three")
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
