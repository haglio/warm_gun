import Foundation
import Testing
@testable import WarmGunKit

@Suite struct PlaylistTests {
    static func file(_ path: String, size: Int64 = 2_000_000,
                     seconds: Double? = 5.0, modifiedAt: Double = 1_000) -> LibraryFile {
        LibraryFile(path: path, fileID: 1, size: size, modified: Date(timeIntervalSince1970: modifiedAt),
                    duration: seconds, videoCodec: "h264", width: 752, height: 960)
    }

    @Test func anEmptyCatalogBuildsAnEmptyPlaylist() {
        var rng = PlaylistSeededRNG(seed: 1)

        let playlist = PlaylistBuilder.build(catalog: Catalog(files: []), options: Filters(),
                                             favoriteKeys: [], trash: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.isEmpty)
    }
}

extension PlaylistTests {
    @Test func onlyTheChosenOrientationEverPlays() {
        var rng = PlaylistSeededRNG(seed: 1)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4"),
            Self.file("1_sorted/beta/landscape/video-two.mp4"),
            Self.file("1_sorted/gamma/portrait/video-three.mp4"),
        ])

        let portrait = PlaylistBuilder.build(catalog: catalog, options: Filters(shape: .portrait),
                                             favoriteKeys: [], trash: [], weights: WatchWeights(), rng: &rng)
        let landscape = PlaylistBuilder.build(catalog: catalog, options: Filters(shape: .landscape),
                                              favoriteKeys: [], trash: [], weights: WatchWeights(), rng: &rng)

        #expect(portrait.sorted() == ["1_sorted/alpha/portrait/video-one.mp4", "1_sorted/gamma/portrait/video-three.mp4"])
        #expect(landscape == ["1_sorted/beta/landscape/video-two.mp4"])
    }
}

extension PlaylistTests {
    @Test func aVideoMarkedTrashNeverComesBack() {
        var rng = PlaylistSeededRNG(seed: 2)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4"),
            Self.file("1_sorted/alpha/portrait/video-two.mp4"),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: Filters(), favoriteKeys: [],
                                             trash: ["1_sorted/alpha/portrait/video-two.mp4"],
                                             weights: WatchWeights(), rng: &rng)

        #expect(playlist == ["1_sorted/alpha/portrait/video-one.mp4"])
    }
}

extension PlaylistTests {
    @Test func aVideoOverTheSizeCapIsLeftOutAndOneExactlyAtItPlays() {
        var rng = PlaylistSeededRNG(seed: 3)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4", size: 2_000_000),
            Self.file("1_sorted/alpha/portrait/video-two.mp4", size: 25_000_001),
            Self.file("1_sorted/alpha/portrait/video-three.mp4", size: 25_000_000),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: Filters(), favoriteKeys: [],
                                             trash: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.sorted() == ["1_sorted/alpha/portrait/video-one.mp4", "1_sorted/alpha/portrait/video-three.mp4"])
    }
}

extension PlaylistTests {
    @Test func fModeShowsOnlyTheFavoritesAndKnowsThemByStem() {
        var rng = PlaylistSeededRNG(seed: 4)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4"),
            Self.file("1_sorted/beta/portrait/video-two.mp4"),
            Self.file("1_sorted/gamma/portrait/video-three.mp4"),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: Filters(favoritesOnly: true),
                                             favoriteKeys: ["video-two", "video-absent"], trash: [],
                                             weights: WatchWeights(), rng: &rng)

        #expect(playlist == ["1_sorted/beta/portrait/video-two.mp4"])
    }
}

extension PlaylistTests {
    @Test func shortsKeepsVideosUpToTheBoundAndJudgesUnknownLengthBySize() {
        var rng = PlaylistSeededRNG(seed: 5)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4", seconds: 4.0),
            Self.file("1_sorted/alpha/portrait/video-two.mp4", seconds: 10.0),
            Self.file("1_sorted/alpha/portrait/video-three.mp4", seconds: 10.5),
            Self.file("1_sorted/alpha/portrait/video-four.mp4", size: 20_000_000, seconds: nil),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: Filters(types: [.short]),
                                             favoriteKeys: [], trash: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.sorted() == ["1_sorted/alpha/portrait/video-one.mp4", "1_sorted/alpha/portrait/video-two.mp4"])
    }
}

extension PlaylistTests {
    @Test func latestIsNewestFirstTiedOnPathAndCarriesNoWeighting() {
        var rng = PlaylistSeededRNG(seed: 6)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-old.mp4", modifiedAt: 1_000),
            Self.file("1_sorted/gamma/portrait/video-tied-b.mp4", modifiedAt: 2_000),
            Self.file("1_sorted/beta/portrait/video-tied-a.mp4", modifiedAt: 2_000),
            Self.file("1_sorted/alpha/portrait/video-new.mp4", modifiedAt: 3_000),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/video-new.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125))])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: Filters(latest: true),
                                             favoriteKeys: [], trash: [], weights: weights, rng: &rng)

        #expect(playlist == [
            "1_sorted/alpha/portrait/video-new.mp4",
            "1_sorted/beta/portrait/video-tied-a.mp4",
            "1_sorted/gamma/portrait/video-tied-b.mp4",
            "1_sorted/alpha/portrait/video-old.mp4",
        ])
    }
}

extension PlaylistTests {
    @Test func shuffleLeavesAChronicallySkippedVideoOutOfMostBuilds() {
        var rng = PlaylistSeededRNG(seed: 8)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-one.mp4"),
            Self.file("1_sorted/alpha/portrait/video-two.mp4"),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/video-two.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125))])

        let builds = (0..<200).map { _ in
            PlaylistBuilder.build(catalog: catalog, options: Filters(), favoriteKeys: [],
                                  trash: [], weights: weights, rng: &rng)
        }

        #expect(builds.allSatisfy { $0.contains("1_sorted/alpha/portrait/video-one.mp4") })
        let skipped = builds.filter { $0.contains("1_sorted/alpha/portrait/video-two.mp4") }.count
        #expect(skipped > 5 && skipped < 60)
    }
}

extension PlaylistTests {
    @Test func oneSeedAlwaysBuildsTheSamePlaylistAndAnotherSeedDoesNot() {
        let catalog = Catalog(files: (0..<24).map { Self.file("1_sorted/alpha/portrait/video-\($0).mp4") })
        func build(seed: UInt64) -> [String] {
            var rng = PlaylistSeededRNG(seed: seed)
            return PlaylistBuilder.build(catalog: catalog, options: Filters(), favoriteKeys: [],
                                         trash: [], weights: WatchWeights(), rng: &rng)
        }

        #expect(build(seed: 11) == build(seed: 11))
        #expect(build(seed: 11) != build(seed: 12))
        #expect(build(seed: 11).sorted() == catalog.videos.map(\.path).sorted())
        #expect(build(seed: 11) != catalog.videos.map(\.path))
    }
}

extension PlaylistTests {
    @Test func theFiltersCompose() {
        var rng = PlaylistSeededRNG(seed: 9)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/landscape/video-one.mp4"),
            Self.file("1_sorted/alpha/portrait/video-two.mp4"),
            Self.file("1_sorted/beta/portrait/video-three.mp4", size: 30_000_000),
            Self.file("1_sorted/beta/portrait/video-four.mp4"),
            Self.file("1_sorted/gamma/portrait/video-five.mp4", seconds: 30.0),
            Self.file("1_sorted/gamma/portrait/video-six.mp4", seconds: 6.0),
        ])
        let favorites: Set<String> = ["video-one", "video-two", "video-three", "video-five", "video-six"]
        var options = Filters(shape: .portrait, favoritesOnly: true, types: [.short])

        let strict = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: favorites,
                                           trash: ["1_sorted/alpha/portrait/video-two.mp4"],
                                           weights: WatchWeights(), rng: &rng)
        #expect(strict == ["1_sorted/gamma/portrait/video-six.mp4"])

        options.favoritesOnly = false
        let relaxed = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: favorites,
                                            trash: ["1_sorted/alpha/portrait/video-two.mp4"],
                                            weights: WatchWeights(), rng: &rng)
        #expect(relaxed.sorted() == ["1_sorted/beta/portrait/video-four.mp4", "1_sorted/gamma/portrait/video-six.mp4"])
    }
}

extension PlaylistTests {
    @Test func aLovedVideoOpensTheRunFarMoreOftenThanANeutralOne() {
        var rng = PlaylistSeededRNG(seed: 10)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/video-plain.mp4"),
            Self.file("1_sorted/alpha/portrait/video-loved.mp4"),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/video-loved.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 8.0))])

        let lovedFirst = (0..<200).filter { _ in
            PlaylistBuilder.build(catalog: catalog, options: Filters(), favoriteKeys: [],
                                  trash: [], weights: weights, rng: &rng).first == "1_sorted/alpha/portrait/video-loved.mp4"
        }.count

        #expect(lovedFirst > 150)
    }
}

extension PlaylistTests {
    @Test func theFiltersSurviveAJSONRoundTrip() throws {
        let options = Filters(shape: .landscape, favoritesOnly: true, types: [.short, .genauFlick],
                                    shortsMaxSeconds: 8, latest: true, maxBytes: 12_000_000)

        let data = try JSONEncoder().encode(options)

        #expect(try JSONDecoder().decode(Filters.self, from: data) == options)
    }
}

extension PlaylistTests {
    @Test func persistedFiltersFromBeforeANewSwitchStillDecode() throws {
        let old = Data(#"{"orientation":"landscape","favoritesOnly":true}"#.utf8)
        let options = try JSONDecoder().decode(Filters.self, from: old)
        #expect(options.shape == .landscape)
        #expect(options.favoritesOnly)
        #expect(options.shortsMaxSeconds == 10)
        #expect(options.maxBytes == 25_000_000)
    }
}

extension PlaylistTests {
    @Test func theSizeCeilingAndShortsThresholdAreTheOptionsNotConstants() {
        var rng = PlaylistSeededRNG(seed: 9)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/video-small.mp4", size: 5_000_000, seconds: 8),
            PlaylistTests.file("1_sorted/alpha/portrait/video-large.mp4", size: 20_000_000, seconds: 12),
        ])

        var sized = Filters()
        sized.maxBytes = 10_000_000
        #expect(PlaylistBuilder.build(catalog: catalog, options: sized, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/video-small.mp4"])

        var shorts = Filters()
        shorts.types = [.short]
        shorts.shortsMaxSeconds = 9
        #expect(PlaylistBuilder.build(catalog: catalog, options: shorts, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/video-small.mp4"])
    }
}

extension PlaylistTests {
    @Test func everyVideoFallsIntoExactlyOneType() {
        let genau = PlaylistTests.file("1_sorted/alpha_genau/portrait/video-a.mp4", seconds: 4)
        let short = PlaylistTests.file("1_sorted/alpha/portrait/video-b.mp4", seconds: 8)
        let long = PlaylistTests.file("1_sorted/alpha/portrait/video-c.mp4", seconds: 40)
        let unknown = PlaylistTests.file("1_sorted/alpha/portrait/video-d.mp4", size: 20_000_000, seconds: nil)
        let videos = Catalog(files: [genau, short, long, unknown]).videos
        #expect(VideoType.classify(videos[0], shortsMaxSeconds: 10) == .genauFlick)
        #expect(VideoType.classify(videos[1], shortsMaxSeconds: 10) == .short)
        #expect(VideoType.classify(videos[2], shortsMaxSeconds: 10) == .fullLength)
        #expect(VideoType.classify(videos[3], shortsMaxSeconds: 10) == .fullLength)
    }

    @Test func theTypeTheDesktopRecordedOutranksEveryGuessHere() {
        let long = Catalog(files: [Self.file("1_sorted/alpha/portrait/video-c.mp4", seconds: 40)]).videos[0]
        let inGenauLane = Catalog(files: [Self.file("1_sorted/alpha_genau/portrait/video-a.mp4", seconds: 4)]).videos[0]

        #expect(VideoType.classify(long, shortsMaxSeconds: 10, recorded: "short") == .short)
        #expect(VideoType.classify(long, shortsMaxSeconds: 10, recorded: "excerpt") == .excerpt)
        #expect(VideoType.classify(inGenauLane, shortsMaxSeconds: 10, recorded: "full_length") == .fullLength)
        #expect(VideoType.classify(long, shortsMaxSeconds: 10, recorded: "medium_length") == .fullLength)
    }

    @Test func theTypeButtonsNarrowTheRecordedTypesToo() {
        var rng = PlaylistSeededRNG(seed: 31)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/video-a.mp4", seconds: 40),
            PlaylistTests.file("1_sorted/alpha/portrait/video-b.mp4", seconds: 40),
        ])
        var options = Filters()
        options.types = [.excerpt]

        let built = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                          trash: [], weights: WatchWeights(),
                                          recordedTypes: ["1_sorted/alpha/portrait/video-a.mp4": "excerpt"],
                                          rng: &rng)

        #expect(built == ["1_sorted/alpha/portrait/video-a.mp4"])
    }

    @Test func theTypeButtonsNarrowTheBuild() {
        var rng = PlaylistSeededRNG(seed: 5)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha_genau/portrait/video-a.mp4", seconds: 4),
            PlaylistTests.file("1_sorted/alpha/portrait/video-b.mp4", seconds: 8),
            PlaylistTests.file("1_sorted/alpha/portrait/video-c.mp4", seconds: 40),
        ])
        var options = Filters()
        options.types = [.short]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/video-b.mp4"])
        options.types = [.genauFlick, .fullLength]
        let both = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                         trash: [], weights: WatchWeights(), rng: &rng)
        #expect(Set(both) == ["1_sorted/alpha_genau/portrait/video-a.mp4",
                              "1_sorted/alpha/portrait/video-c.mp4"])
    }

    @Test func aPersistedShortsOnlyFiltersMigrateToTheTypes() throws {
        let old = Data(#"{"orientation":"portrait","shortsOnly":true}"#.utf8)
        #expect(try JSONDecoder().decode(Filters.self, from: old).types == [.short])
        let plain = Data(#"{"orientation":"portrait"}"#.utf8)
        #expect(try JSONDecoder().decode(Filters.self, from: plain).types == Set(VideoType.allCases))
    }
}

extension PlaylistTests {
    @Test func aVideoTheServerNeverTimedIsJudgedByMeasureThenBySize() {
        let video = Catalog(files: [PlaylistTests.file("1_sorted/alpha/portrait/video-a.mp4",
                                                      size: 2_000_000, seconds: nil)]).videos[0]
        #expect(VideoType.classify(video, shortsMaxSeconds: 10, measuredSeconds: 40) == .fullLength)
        #expect(VideoType.classify(video, shortsMaxSeconds: 10, measuredSeconds: nil) == .short)
        let big = Catalog(files: [PlaylistTests.file("1_sorted/alpha/portrait/video-b.mp4",
                                                     size: 20_000_000, seconds: nil)]).videos[0]
        #expect(VideoType.classify(big, shortsMaxSeconds: 10, measuredSeconds: nil) == .fullLength)
    }

    @Test func genauLoopsIgnoreTheShapeFilterAndMeasuredTimesReachTheBuild() {
        var rng = PlaylistSeededRNG(seed: 11)
        let genau = LibraryFile(path: "genau/clips/2D/AI/loop-one.mp4", fileID: 9, size: 2_000_000,
                                modified: Date(timeIntervalSince1970: 0), duration: nil,
                                videoCodec: nil, width: 1920, height: 1080)
        let catalog = Catalog(files: [
            genau,
            PlaylistTests.file("1_sorted/alpha/portrait/video-small.mp4", size: 2_000_000, seconds: nil),
        ])
        var options = Filters(shape: .portrait)
        options.types = [.genauFlick]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), rng: &rng)
                == ["genau/clips/2D/AI/loop-one.mp4"])
        options.types = [.fullLength]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(),
                                      measuredSeconds: ["1_sorted/alpha/portrait/video-small.mp4": 40], rng: &rng)
                == ["1_sorted/alpha/portrait/video-small.mp4"])
    }
}

extension PlaylistTests {
    private static func nonAI(_ path: String, size: Int64 = 300_000_000,
                              width: Int? = 1920, height: Int? = 1080) -> LibraryFile {
        LibraryFile(path: path, fileID: 7, size: size, modified: Date(timeIntervalSince1970: 0),
                    duration: nil, videoCodec: nil, width: width, height: height)
    }

    @Test func theOverlayNamesTheLanesTheRepoCannot() {
        let overlay = ContentOverlay(lanes: [
            ContentOverlay.Lane(prefix: "non_AI/alpha/special", type: .excerpt, shape: .landscape),
            ContentOverlay.Lane(prefix: "non_AI/tall", type: .fullLength, shape: .portrait),
        ])
        let special = Catalog(files: [Self.nonAI("non_AI/alpha/special/scene-one.mp4")]).videos[0]
        let tall = Catalog(files: [Self.nonAI("non_AI/tall/scene-two.mp4")]).videos[0]
        let plain = Catalog(files: [Self.nonAI("non_AI/beta/scene-three.mp4")]).videos[0]
        #expect(VideoType.classify(special, shortsMaxSeconds: 10, overlay: overlay) == .excerpt)
        #expect(VideoType.classify(plain, shortsMaxSeconds: 10, overlay: overlay) == .fullLength)
        #expect(overlay.lane(for: tall.path)?.shape == .portrait)

        var rng = PlaylistSeededRNG(seed: 13)
        var options = Filters(shape: .landscape)
        options.types = [.excerpt]
        let catalog = Catalog(files: [Self.nonAI("non_AI/alpha/special/scene-one.mp4"),
                                      Self.nonAI("non_AI/beta/scene-three.mp4")])
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), overlay: overlay, rng: &rng)
                == ["non_AI/alpha/special/scene-one.mp4"])
    }

    @Test func theLaneShapeOutranksThePixelsAndTheSizeGateSparesTheScenes() {
        let overlay = ContentOverlay(lanes: [
            ContentOverlay.Lane(prefix: "non_AI/tall", type: .fullLength, shape: .portrait),
        ])
        var rng = PlaylistSeededRNG(seed: 17)
        let catalog = Catalog(files: [
            Self.nonAI("non_AI/tall/scene-two.mp4"),
            PlaylistTests.file("1_sorted/alpha/portrait/video-huge.mp4", size: 300_000_000, seconds: 40),
        ])
        var options = Filters(shape: .portrait)
        options.types = [.fullLength]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      trash: [], weights: WatchWeights(), overlay: overlay, rng: &rng)
                == ["non_AI/tall/scene-two.mp4"])
    }
}

extension PlaylistTests {
    @Test func theBundledOverlayDecodesInTheShapeItsExampleDocuments() throws {
        let json = Data(#"""
        {"lanes": [
           {"prefix": "non_AI/alpha/carved", "type": "excerpt",
            "orientation": "landscape"},
           {"prefix": "non_AI/tall", "type": "full_length",
            "orientation": "portrait"}]}
        """#.utf8)

        let overlay = try JSONDecoder().decode(ContentOverlay.self, from: json)

        #expect(overlay.lanes.map(\.type) == [.excerpt, .fullLength])
    }

    @Test func anOverlayStillNamingTheExcerptsChipDecodesTheSame() throws {
        let json = Data(#"""
        {"lanes": [{"prefix": "non_AI/alpha/carved", "type": "excerpt",
                    "orientation": "landscape", "label": "Carved"}]}
        """#.utf8)

        let overlay = try JSONDecoder().decode(ContentOverlay.self, from: json)

        #expect(overlay.lanes.map(\.type) == [.excerpt])
    }

    @Test func theClipsButtonTakesTheShortsAndTheCarvedScenesInAndOutTogether() {
        var options = Filters(types: [.genauFlick, .fullLength])
        #expect(!options.includes(VideoType.clips))

        options.setIncluded(VideoType.clips, true)
        #expect(options.types == Set(VideoType.allCases))
        #expect(options.includes(VideoType.clips))

        options.setIncluded(VideoType.clips, false)
        #expect(options.types == [.genauFlick, .fullLength])
    }

    @Test func filtersHoldingOnlyOneOfTheTwoReadAsClipsOff() {
        #expect(!Filters(types: [.short]).includes(VideoType.clips))
        #expect(!Filters(types: [.excerpt]).includes(VideoType.clips))
    }

    @Test func persistedFiltersKeepTheirTypesThroughTheRename() throws {
        let old = Data(#"{"orientation":"portrait","types":["genau","acts","fullLength"]}"#.utf8)

        let restored = try JSONDecoder().decode(Filters.self, from: old)

        #expect(restored.types == [.genauFlick, .excerpt, .fullLength])
    }

    @Test func filtersPersistedBeforeGenausClipsWereCalledFlicksKeepsItsGenauType() throws {
        let old = Data(#"{"orientation":"portrait","types":["genau_clip","short"]}"#.utf8)

        let restored = try JSONDecoder().decode(Filters.self, from: old)

        #expect(restored.types == [.genauFlick, .short])
    }

    @Test func aSidecarRecordedBeforeGenausClipsWereCalledFlicksStillNamesAFlick() {
        let video = Catalog(files: [PlaylistTests.file("1_sorted/alpha/portrait/video-a.mp4", seconds: 4)]).videos[0]

        #expect(VideoType.classify(video, shortsMaxSeconds: 10, recorded: "genau_clip") == .genauFlick)
        #expect(VideoType.classify(video, shortsMaxSeconds: 10, recorded: "genau_flick") == .genauFlick)
    }
}

extension PlaylistTests {
    @Test func aVideoCarryingALabelWhoseButtonIsOffSitsOutAndAnUnlabeledOneAlwaysPlays() {
        var rng = PlaylistSeededRNG(seed: 29)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/video-a.mp4", seconds: 30),
            PlaylistTests.file("1_sorted/alpha/portrait/video-b.mp4", seconds: 30),
            PlaylistTests.file("1_sorted/alpha/portrait/video-c.mp4", seconds: 30),
        ])
        var options = Filters()
        options.disabledActions = ["Second box"]
        let built = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                          trash: [], weights: WatchWeights(),
                                          labels: ["1_sorted/alpha/portrait/video-a.mp4": ["Alpha"],
                                                   "1_sorted/alpha/portrait/video-b.mp4": ["Alpha", "Second box"]],
                                          rng: &rng)
        #expect(Set(built) == ["1_sorted/alpha/portrait/video-a.mp4", "1_sorted/alpha/portrait/video-c.mp4"])
    }

    @Test func filtersSavedBeforeAnyActionButtonWasTurnedOffTurnNoneOff() throws {
        let old = Data(#"{"orientation":"portrait"}"#.utf8)
        #expect(try JSONDecoder().decode(Filters.self, from: old).disabledActions.isEmpty)
    }
}

extension PlaylistTests {
    @Test func aVideoPlaysInItsLanesShapeOrItsOwnAndAFlickInEither() {
        let overlay = ContentOverlay(lanes: [
            ContentOverlay.Lane(prefix: "non_AI/tall", type: .fullLength, shape: .portrait),
        ])
        let upright = Catalog(files: [Self.file("1_sorted/alpha/portrait/video-one.mp4")]).videos[0]
        let laned = Catalog(files: [Self.nonAI("non_AI/tall/scene-two.mp4")]).videos[0]
        let flick = Catalog(files: [LibraryFile(path: "genau/clips/2D/AI/loop-one.mp4", fileID: 9,
                                                size: 2_000_000, modified: Date(timeIntervalSince1970: 0),
                                                duration: nil, videoCodec: nil, width: 1920, height: 1080)]).videos[0]
        let portrait = Filters(shape: .portrait)
        let landscape = Filters(shape: .landscape)

        #expect(PlaylistBuilder.playsInShape(upright, options: portrait, overlay: overlay))
        #expect(!PlaylistBuilder.playsInShape(upright, options: landscape, overlay: overlay))
        #expect(PlaylistBuilder.playsInShape(laned, options: portrait, overlay: overlay))
        #expect(!PlaylistBuilder.playsInShape(laned, options: landscape, overlay: overlay))
        #expect(PlaylistBuilder.playsInShape(flick, options: portrait, overlay: overlay))
        #expect(PlaylistBuilder.playsInShape(flick, options: landscape, overlay: overlay))
    }
}

extension PlaylistTests {
    @Test func aPathUnderTwoLanesFollowsTheLongerPrefixWhicheverIsListedFirst() {
        let wide = ContentOverlay.Lane(prefix: "non_AI/alpha", type: .fullLength, shape: nil)
        let narrow = ContentOverlay.Lane(prefix: "non_AI/alpha/special", type: .excerpt, shape: nil)
        let path = "non_AI/alpha/special/scene-one.mp4"
        #expect(ContentOverlay(lanes: [wide, narrow]).lane(for: path)?.type == .excerpt)
        #expect(ContentOverlay(lanes: [narrow, wide]).lane(for: path)?.type == .excerpt)
    }

    @Test func theRetiredShortsOnlySwitchIsNeverWrittenBack() throws {
        let old = Data(#"{"shape":"portrait","shortsOnly":true}"#.utf8)
        let saved = try JSONEncoder().encode(JSONDecoder().decode(Filters.self, from: old))
        #expect(!String(decoding: saved, as: UTF8.self).contains("shortsOnly"))
    }
}
