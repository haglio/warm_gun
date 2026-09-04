import Foundation
import Testing
@testable import WarmGunKit

/// The build is the one place every browse switch meets the index, so these
/// tests read as little libraries put through the controls sheet.
@Suite struct PlaylistTests {
    /// Every fixture path, source and stem here is invented; the real library
    /// never appears in this repo.
    static func file(_ path: String, size: Int64 = 2_000_000,
                     seconds: Double? = 5.0, modifiedAt: Double = 1_000) -> LibraryFile {
        LibraryFile(path: path, fileID: 1, size: size, modified: Date(timeIntervalSince1970: modifiedAt),
                    duration: seconds, videoCodec: "h264", width: 752, height: 960)
    }

    @Test func anEmptyCatalogBuildsAnEmptyPlaylist() {
        var rng = PlaylistSeededRNG(seed: 1)

        let playlist = PlaylistBuilder.build(catalog: Catalog(files: []), options: BrowseOptions(),
                                             favoriteKeys: [], weird: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.isEmpty)
    }
}

extension PlaylistTests {
    /// The Landscape checkbox picks a whole library, not a subset of one: the
    /// two orientations never mix on screen, and the folder is the authority
    /// because 21 clips in the library are square.
    @Test func onlyTheChosenOrientationEverPlays() {
        var rng = PlaylistSeededRNG(seed: 1)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4"),
            Self.file("1_sorted/beta/landscape/clip-two.mp4"),
            Self.file("1_sorted/gamma/portrait/clip-three.mp4"),
        ])

        let portrait = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(orientation: .portrait),
                                             favoriteKeys: [], weird: [], weights: WatchWeights(), rng: &rng)
        let landscape = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(orientation: .landscape),
                                              favoriteKeys: [], weird: [], weights: WatchWeights(), rng: &rng)

        #expect(portrait.sorted() == ["1_sorted/alpha/portrait/clip-one.mp4", "1_sorted/gamma/portrait/clip-three.mp4"])
        #expect(landscape == ["1_sorted/beta/landscape/clip-two.mp4"])
    }
}

extension PlaylistTests {
    /// A weird mark is the hard removal the weighting is the soft version of:
    /// the clip is gone from every later build, not merely made rarer, and it
    /// stays gone until the next index refresh drops it from the catalog too.
    @Test func aClipMarkedWeirdNeverComesBack() {
        var rng = PlaylistSeededRNG(seed: 2)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4"),
            Self.file("1_sorted/alpha/portrait/clip-two.mp4"),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(), favoriteKeys: [],
                                             weird: ["1_sorted/alpha/portrait/clip-two.mp4"],
                                             weights: WatchWeights(), rng: &rng)

        #expect(playlist == ["1_sorted/alpha/portrait/clip-one.mp4"])
    }
}

extension PlaylistTests {
    /// A handful of legacy HEVC upscales sit in the originals tree at hundreds
    /// of megabytes each, and the phone fetches a clip whole before it plays —
    /// so a file over the cap is minutes of black screen and is left out.
    /// A file exactly at the cap still plays: the cap is what is allowed.
    @Test func aClipOverTheSizeCapIsLeftOutAndOneExactlyAtItPlays() {
        var rng = PlaylistSeededRNG(seed: 3)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4", size: 2_000_000),
            Self.file("1_sorted/alpha/portrait/clip-two.mp4", size: 25_000_001),
            Self.file("1_sorted/alpha/portrait/clip-three.mp4", size: 25_000_000),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(), favoriteKeys: [],
                                             weird: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.sorted() == ["1_sorted/alpha/portrait/clip-one.mp4", "1_sorted/alpha/portrait/clip-three.mp4"])
    }
}

extension PlaylistTests {
    /// F-mode browses the favorites alone. Favorites are held by stem, not by
    /// path, because that is all the desktop's `favs.csv` carries — and stems
    /// are unique library-wide, so the stem names the clip exactly.
    @Test func fModeBrowsesOnlyTheFavoritesAndKnowsThemByStem() {
        var rng = PlaylistSeededRNG(seed: 4)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4"),
            Self.file("1_sorted/beta/portrait/clip-two.mp4"),
            Self.file("1_sorted/gamma/portrait/clip-three.mp4"),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(favoritesOnly: true),
                                             favoriteKeys: ["clip-two", "clip-absent"], weird: [],
                                             weights: WatchWeights(), rng: &rng)

        #expect(playlist == ["1_sorted/beta/portrait/clip-two.mp4"])
    }
}

extension PlaylistTests {
    /// Shorts is a length filter, and a clip whose duration the listing never
    /// reported cannot be shown to be short — so it sits the build out, the
    /// same way Nau's length filter drops what it cannot measure rather than
    /// guessing. The bound is inclusive.
    @Test func shortsKeepsClipsUpToTheBoundAndJudgesUnknownLengthBySize() {
        var rng = PlaylistSeededRNG(seed: 5)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4", seconds: 4.0),
            Self.file("1_sorted/alpha/portrait/clip-two.mp4", seconds: 10.0),
            Self.file("1_sorted/alpha/portrait/clip-three.mp4", seconds: 10.5),
            // Unknown length: the size stands in — a big file reads full length.
            Self.file("1_sorted/alpha/portrait/clip-four.mp4", size: 20_000_000, seconds: nil),
        ])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(types: [.short]),
                                             favoriteKeys: [], weird: [], weights: WatchWeights(), rng: &rng)

        #expect(playlist.sorted() == ["1_sorted/alpha/portrait/clip-one.mp4", "1_sorted/alpha/portrait/clip-two.mp4"])
    }
}

extension PlaylistTests {
    /// Latest is a review order: newest first, and deliberately unweighted, so a
    /// clip that has been skipped away from a dozen times still surfaces when it
    /// is new. Clips filed in the same second fall back to their path, so the
    /// order is one order and not whatever the index happened to hold.
    @Test func latestIsNewestFirstTiedOnPathAndCarriesNoWeighting() {
        var rng = PlaylistSeededRNG(seed: 6)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-old.mp4", modifiedAt: 1_000),
            Self.file("1_sorted/gamma/portrait/clip-tied-b.mp4", modifiedAt: 2_000),
            Self.file("1_sorted/beta/portrait/clip-tied-a.mp4", modifiedAt: 2_000),
            Self.file("1_sorted/alpha/portrait/clip-new.mp4", modifiedAt: 3_000),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/clip-new.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125))])

        let playlist = PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(latest: true),
                                             favoriteKeys: [], weird: [], weights: weights, rng: &rng)

        #expect(playlist == [
            "1_sorted/alpha/portrait/clip-new.mp4",
            "1_sorted/beta/portrait/clip-tied-a.mp4",
            "1_sorted/gamma/portrait/clip-tied-b.mp4",
            "1_sorted/alpha/portrait/clip-old.mp4",
        ])
    }
}

extension PlaylistTests {
    /// Shuffle thins rather than removes: a clip skipped away from again and
    /// again sits most builds out — the soft counterpart of the weird gesture —
    /// while a clip at neutral weight or above is in every single build.
    @Test func shuffleLeavesAChronicallySkippedClipOutOfMostBuilds() {
        var rng = PlaylistSeededRNG(seed: 8)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-one.mp4"),
            Self.file("1_sorted/alpha/portrait/clip-two.mp4"),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/clip-two.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 0.125))])

        let builds = (0..<200).map { _ in
            PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(), favoriteKeys: [],
                                  weird: [], weights: weights, rng: &rng)
        }

        #expect(builds.allSatisfy { $0.contains("1_sorted/alpha/portrait/clip-one.mp4") })
        let skipped = builds.filter { $0.contains("1_sorted/alpha/portrait/clip-two.mp4") }.count
        #expect(skipped > 5 && skipped < 60)
    }
}

extension PlaylistTests {
    /// The prefetcher fetches ahead *and* behind, which only works because the
    /// run is knowable in advance: one seed is one playlist, every time. It is
    /// still a shuffle — another seed gives another order.
    @Test func oneSeedAlwaysBuildsTheSamePlaylistAndAnotherSeedDoesNot() {
        let catalog = Catalog(files: (0..<24).map { Self.file("1_sorted/alpha/portrait/clip-\($0).mp4") })
        func build(seed: UInt64) -> [String] {
            var rng = PlaylistSeededRNG(seed: seed)
            return PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(), favoriteKeys: [],
                                         weird: [], weights: WatchWeights(), rng: &rng)
        }

        #expect(build(seed: 11) == build(seed: 11))
        #expect(build(seed: 11) != build(seed: 12))
        #expect(build(seed: 11).sorted() == catalog.clips.map(\.path).sorted())
        #expect(build(seed: 11) != catalog.clips.map(\.path))
    }
}

extension PlaylistTests {
    /// Every switch narrows the same list, so with them all on only a clip that
    /// clears all five plays. Each of the others here fails exactly one test,
    /// which is what makes relaxing one switch bring back exactly one clip.
    @Test func theFiltersCompose() {
        var rng = PlaylistSeededRNG(seed: 9)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/landscape/clip-one.mp4"),
            Self.file("1_sorted/alpha/portrait/clip-two.mp4"),
            Self.file("1_sorted/beta/portrait/clip-three.mp4", size: 30_000_000),
            Self.file("1_sorted/beta/portrait/clip-four.mp4"),
            Self.file("1_sorted/gamma/portrait/clip-five.mp4", seconds: 30.0),
            Self.file("1_sorted/gamma/portrait/clip-six.mp4", seconds: 6.0),
        ])
        let favorites: Set<String> = ["clip-one", "clip-two", "clip-three", "clip-five", "clip-six"]
        var options = BrowseOptions(orientation: .portrait, favoritesOnly: true, types: [.short])

        let strict = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: favorites,
                                           weird: ["1_sorted/alpha/portrait/clip-two.mp4"],
                                           weights: WatchWeights(), rng: &rng)
        #expect(strict == ["1_sorted/gamma/portrait/clip-six.mp4"])

        options.favoritesOnly = false
        let relaxed = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: favorites,
                                            weird: ["1_sorted/alpha/portrait/clip-two.mp4"],
                                            weights: WatchWeights(), rng: &rng)
        #expect(relaxed.sorted() == ["1_sorted/beta/portrait/clip-four.mp4", "1_sorted/gamma/portrait/clip-six.mp4"])
    }
}

extension PlaylistTests {
    /// The counts have to reach the ordering, not only the inclusion draw:
    /// a loved clip is what the run opens on, most of the time.
    @Test func aLovedClipOpensTheRunFarMoreOftenThanANeutralOne() {
        var rng = PlaylistSeededRNG(seed: 10)
        let catalog = Catalog(files: [
            Self.file("1_sorted/alpha/portrait/clip-plain.mp4"),
            Self.file("1_sorted/alpha/portrait/clip-loved.mp4"),
        ])
        let weights = WatchWeights(sidecars: ["1_sorted/alpha/portrait/clip-loved.mp4":
            Sidecar(video: nil, sourceImage: nil, watch: Sidecar.Watch(weight: 8.0))])

        let lovedFirst = (0..<200).filter { _ in
            PlaylistBuilder.build(catalog: catalog, options: BrowseOptions(), favoriteKeys: [],
                                  weird: [], weights: weights, rng: &rng).first == "1_sorted/alpha/portrait/clip-loved.mp4"
        }.count

        #expect(lovedFirst > 150)
    }
}

extension PlaylistTests {
    /// The controls sheet is where it was left: the switches are saved between
    /// launches, so the whole record has to survive a JSON round trip.
    @Test func theBrowseSwitchesSurviveAJSONRoundTrip() throws {
        let options = BrowseOptions(orientation: .landscape, favoritesOnly: true, types: [.short, .genau],
                                    shortsMaxSeconds: 8, latest: true, maxBytes: 12_000_000)

        let data = try JSONEncoder().encode(options)

        #expect(try JSONDecoder().decode(BrowseOptions.self, from: data) == options)
    }
}

extension PlaylistTests {
    @Test func aPersistedBrowseFromBeforeANewSwitchStillDecodes() throws {
        // Settings are persisted and reloaded across app updates: a blob written
        // before a switch existed must decode with that switch at its default,
        // not throw away every saved control at once.
        let old = Data(#"{"orientation":"landscape","favoritesOnly":true}"#.utf8)
        let options = try JSONDecoder().decode(BrowseOptions.self, from: old)
        #expect(options.orientation == .landscape)
        #expect(options.favoritesOnly)
        #expect(options.shortsMaxSeconds == 10)
        #expect(options.maxBytes == 25_000_000)
    }
}

extension PlaylistTests {
    @Test func theSizeCeilingAndShortsThresholdAreTheOptionsNotConstants() {
        var rng = PlaylistSeededRNG(seed: 9)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/clip-small.mp4", size: 5_000_000, seconds: 8),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-large.mp4", size: 20_000_000, seconds: 12),
        ])

        var sized = BrowseOptions()
        sized.maxBytes = 10_000_000
        #expect(PlaylistBuilder.build(catalog: catalog, options: sized, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/clip-small.mp4"])

        var shorts = BrowseOptions()
        shorts.types = [.short]
        shorts.shortsMaxSeconds = 9
        #expect(PlaylistBuilder.build(catalog: catalog, options: shorts, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/clip-small.mp4"])
    }
}

extension PlaylistTests {
    @Test func everyClipFallsIntoExactlyOneType() {
        // Genau loops are named by their source folder (the desktop delivers
        // them from origenerator's genau lane); shorts are by running time; the
        // rest — unknown durations included — are full length. Act-based types
        // wait on the metadata sidecar index and classify nowhere yet.
        let genau = PlaylistTests.file("1_sorted/alpha_genau/portrait/clip-a.mp4", seconds: 4)
        let short = PlaylistTests.file("1_sorted/alpha/portrait/clip-b.mp4", seconds: 8)
        let long = PlaylistTests.file("1_sorted/alpha/portrait/clip-c.mp4", seconds: 40)
        let unknown = PlaylistTests.file("1_sorted/alpha/portrait/clip-d.mp4", size: 20_000_000, seconds: nil)
        let clips = Catalog(files: [genau, short, long, unknown]).clips
        #expect(ClipType.classify(clips[0], shortsMaxSeconds: 10) == .genau)
        #expect(ClipType.classify(clips[1], shortsMaxSeconds: 10) == .short)
        #expect(ClipType.classify(clips[2], shortsMaxSeconds: 10) == .fullLength)
        #expect(ClipType.classify(clips[3], shortsMaxSeconds: 10) == .fullLength)
    }

    @Test func theTypeCheckboxesNarrowTheBuild() {
        var rng = PlaylistSeededRNG(seed: 5)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha_genau/portrait/clip-a.mp4", seconds: 4),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-b.mp4", seconds: 8),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-c.mp4", seconds: 40),
        ])
        var options = BrowseOptions()
        options.types = [.short]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), rng: &rng)
                == ["1_sorted/alpha/portrait/clip-b.mp4"])
        options.types = [.genau, .fullLength]
        let both = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                         weird: [], weights: WatchWeights(), rng: &rng)
        #expect(Set(both) == ["1_sorted/alpha_genau/portrait/clip-a.mp4",
                              "1_sorted/alpha/portrait/clip-c.mp4"])
    }

    @Test func aPersistedShortsOnlyBrowseMigratesToTheTypeCheckboxes() throws {
        // The sheet used to have one "shorts only" switch; a blob persisted
        // with it on must come back as the shorts checkbox alone, and one
        // without it as every type.
        let old = Data(#"{"orientation":"portrait","shortsOnly":true}"#.utf8)
        #expect(try JSONDecoder().decode(BrowseOptions.self, from: old).types == [.short])
        let plain = Data(#"{"orientation":"portrait"}"#.utf8)
        #expect(try JSONDecoder().decode(BrowseOptions.self, from: plain).types == Set(ClipType.allCases))
    }
}

extension PlaylistTests {
    @Test func aClipTheServerNeverTimedIsJudgedByMeasureThenBySize() {
        // The real pCloud listing carries no durations at all, so the phone
        // measures each clip as it lands in the cache — and until it has, the
        // size stands in (the originals run near half a megabyte a second).
        let clip = Catalog(files: [PlaylistTests.file("1_sorted/alpha/portrait/clip-a.mp4",
                                                      size: 2_000_000, seconds: nil)]).clips[0]
        #expect(ClipType.classify(clip, shortsMaxSeconds: 10, measuredSeconds: 40) == .fullLength)
        #expect(ClipType.classify(clip, shortsMaxSeconds: 10, measuredSeconds: nil) == .short)
        let big = Catalog(files: [PlaylistTests.file("1_sorted/alpha/portrait/clip-b.mp4",
                                                     size: 20_000_000, seconds: nil)]).clips[0]
        #expect(ClipType.classify(big, shortsMaxSeconds: 10, measuredSeconds: nil) == .fullLength)
    }

    @Test func genauLoopsIgnoreTheOrientationFilterAndMeasuredTimesReachTheBuild() {
        // A genau loop has no orientation folder — it plays whichever way the
        // phone is held; and a measured duration must beat the size stand-in.
        var rng = PlaylistSeededRNG(seed: 11)
        let genau = LibraryFile(path: "genau/clips/loop-one.mp4", fileID: 9, size: 2_000_000,
                                modified: Date(timeIntervalSince1970: 0), duration: nil,
                                videoCodec: nil, width: 1920, height: 1080)
        let catalog = Catalog(files: [
            genau,
            PlaylistTests.file("1_sorted/alpha/portrait/clip-small.mp4", size: 2_000_000, seconds: nil),
        ])
        var options = BrowseOptions(orientation: .portrait)
        options.types = [.genau]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), rng: &rng)
                == ["genau/clips/loop-one.mp4"])
        options.types = [.fullLength]
        // Measured as 40 s, the small file stops reading as a short.
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(),
                                      measuredSeconds: ["1_sorted/alpha/portrait/clip-small.mp4": 40], rng: &rng)
                == ["1_sorted/alpha/portrait/clip-small.mp4"])
    }
}

extension PlaylistTests {
    private static func nonAI(_ path: String, size: Int64 = 300_000_000,
                              width: Int? = 1920, height: Int? = 1080) -> LibraryFile {
        LibraryFile(path: path, fileID: 7, size: size, modified: Date(timeIntervalSince1970: 0),
                    duration: nil, videoCodec: nil, width: width, height: height)
    }

    @Test func theOverlayNamesTheLanesTheRepoCannot() {
        // The non-AI buckets' folder names are library content, so which
        // bucket is which TYPE comes from a git-ignored overlay: a lane maps a
        // path prefix to a type and, where the folder dictates one, an
        // orientation. Everything unmatched under non_AI is a full-length
        // scene.
        let overlay = ContentOverlay(lanes: [
            ContentOverlay.Lane(prefix: "non_AI/alpha/special", type: .acts, orientation: .landscape, label: "Special"),
            ContentOverlay.Lane(prefix: "non_AI/tall", type: .fullLength, orientation: .portrait, label: nil),
        ])
        let special = Catalog(files: [Self.nonAI("non_AI/alpha/special/scene-one.mp4")]).clips[0]
        let tall = Catalog(files: [Self.nonAI("non_AI/tall/scene-two.mp4")]).clips[0]
        let plain = Catalog(files: [Self.nonAI("non_AI/beta/scene-three.mp4")]).clips[0]
        #expect(ClipType.classify(special, shortsMaxSeconds: 10, overlay: overlay) == .acts)
        #expect(ClipType.classify(plain, shortsMaxSeconds: 10, overlay: overlay) == .fullLength)
        #expect(overlay.lane(for: tall.path)?.orientation == .portrait)
        #expect(overlay.actsLabel == "Special")

        var rng = PlaylistSeededRNG(seed: 13)
        var options = BrowseOptions(orientation: .landscape)
        options.types = [.acts]
        let catalog = Catalog(files: [Self.nonAI("non_AI/alpha/special/scene-one.mp4"),
                                      Self.nonAI("non_AI/beta/scene-three.mp4")])
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), overlay: overlay, rng: &rng)
                == ["non_AI/alpha/special/scene-one.mp4"])
    }

    @Test func theLaneOrientationOutranksThePixelsAndTheSizeGateSparesTheScenes() {
        // A portrait-lane scene follows its lane whatever its pixels say, and
        // the size ceiling exists to keep legacy monsters out of the AI
        // originals — a 300 MB real scene must not be filtered by it.
        let overlay = ContentOverlay(lanes: [
            ContentOverlay.Lane(prefix: "non_AI/tall", type: .fullLength, orientation: .portrait, label: nil),
        ])
        var rng = PlaylistSeededRNG(seed: 17)
        let catalog = Catalog(files: [
            Self.nonAI("non_AI/tall/scene-two.mp4"),   // 1920x1080 pixels, portrait lane
            PlaylistTests.file("1_sorted/alpha/portrait/clip-huge.mp4", size: 300_000_000, seconds: 40),
        ])
        var options = BrowseOptions(orientation: .portrait)
        options.types = [.fullLength]
        #expect(PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                      weird: [], weights: WatchWeights(), overlay: overlay, rng: &rng)
                == ["non_AI/tall/scene-two.mp4"])
    }
}

extension PlaylistTests {
    @Test func theActsCheckboxAlsoCatchesAIClipsByTheirRecordedAct() {
        // "Type" is not one field anywhere: genau is a source lane, shorts a
        // running time, and acts an entry in the sidecar's video.action — 43
        // distinct values on the real library. The overlay's act_queries name
        // which of those count, matched the desktop's way: normalized
        // contiguous substring.
        let overlay = ContentOverlay(lanes: [], actQueries: ["special"])
        #expect(overlay.matchesActQuery("Very  Special act") == true)
        #expect(overlay.matchesActQuery("plain") == false)

        var rng = PlaylistSeededRNG(seed: 23)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/clip-a.mp4", seconds: 30),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-b.mp4", seconds: 30),
        ])
        var options = BrowseOptions()
        options.types = [.acts]
        let built = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                          weird: [], weights: WatchWeights(), overlay: overlay,
                                          acts: ["1_sorted/alpha/portrait/clip-a.mp4": "special act"], rng: &rng)
        #expect(built == ["1_sorted/alpha/portrait/clip-a.mp4"])
    }

    @Test func anOverlayWithoutActQueriesStillDecodes() throws {
        let old = Data(#"{"lanes": []}"#.utf8)
        #expect(try JSONDecoder().decode(ContentOverlay.self, from: old).actQueries.isEmpty)
    }
}

extension PlaylistTests {
    @Test func theActButtonsBucketEveryClipAndCombine() {
        // Eight combinable act buttons, overlay-defined (the words are library
        // vocabulary): a clip lands in the first bucket whose query matches its
        // recorded act, and in the catch-all otherwise — including clips with
        // no act at all. Deselecting a bucket hides its clips.
        let overlay = ContentOverlay(lanes: [], actFilters: [
            ContentOverlay.ActFilter(label: "AL", queries: ["alpha"], isOther: false),
            ContentOverlay.ActFilter(label: "BE", queries: ["beta"], isOther: false),
            ContentOverlay.ActFilter(label: "O", queries: [], isOther: true),
        ])
        #expect(overlay.actBucket(for: "big alpha act") == "AL")
        #expect(overlay.actBucket(for: "beta") == "BE")
        #expect(overlay.actBucket(for: "gamma") == "O")
        #expect(overlay.actBucket(for: nil) == "O")

        var rng = PlaylistSeededRNG(seed: 29)
        let catalog = Catalog(files: [
            PlaylistTests.file("1_sorted/alpha/portrait/clip-a.mp4", seconds: 30),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-b.mp4", seconds: 30),
            PlaylistTests.file("1_sorted/alpha/portrait/clip-c.mp4", seconds: 30),
        ])
        var options = BrowseOptions()
        options.disabledActs = ["BE", "O"]
        let built = PlaylistBuilder.build(catalog: catalog, options: options, favoriteKeys: [],
                                          weird: [], weights: WatchWeights(), overlay: overlay,
                                          acts: ["1_sorted/alpha/portrait/clip-a.mp4": "alpha",
                                                 "1_sorted/alpha/portrait/clip-b.mp4": "beta"], rng: &rng)
        #expect(built == ["1_sorted/alpha/portrait/clip-a.mp4"])  // c has no act -> O -> hidden
    }

    @Test func anOverlayOrBrowseWithoutActFiltersChangesNothing() throws {
        // No filters defined -> no bucketing, nothing hidden; and an old
        // persisted browse without the key decodes with none disabled.
        #expect(ContentOverlay(lanes: []).actBucket(for: "anything") == nil)
        let old = Data(#"{"orientation":"portrait"}"#.utf8)
        #expect(try JSONDecoder().decode(BrowseOptions.self, from: old).disabledActs.isEmpty)
    }
}
