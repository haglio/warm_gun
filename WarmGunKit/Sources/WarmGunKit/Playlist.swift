import Foundation

/// Every switch on the controls sheet, in one value.
///
/// A plain record with nothing derived in it, so the app can persist it and hand
/// it straight back on the next launch — and so a rebuild is a pure function of
/// this plus the index, with no network in it and nothing to invalidate.
public struct BrowseOptions: Codable, Equatable, Sendable {
    public var orientation: Orientation
    public var favoritesOnly: Bool
    public var shortsOnly: Bool
    public var shortsMaxSeconds: Double
    public var latest: Bool
    /// The size ceiling that keeps the legacy HEVC files sitting in the
    /// originals tree out: the phone fetches a clip whole before it plays, so an
    /// outlier is minutes of black screen rather than a slow start.
    public var maxBytes: Int64

    public init(orientation: Orientation = .portrait, favoritesOnly: Bool = false,
                shortsOnly: Bool = false, shortsMaxSeconds: Double = 10,
                latest: Bool = false, maxBytes: Int64 = 25_000_000) {
        self.orientation = orientation
        self.favoritesOnly = favoritesOnly
        self.shortsOnly = shortsOnly
        self.shortsMaxSeconds = shortsMaxSeconds
        self.latest = latest
        self.maxBytes = maxBytes
    }

    /// A blob persisted before a switch existed decodes with that switch at its
    /// default — an app update must never cost the saved controls.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrowseOptions()
        orientation = try c.decodeIfPresent(Orientation.self, forKey: .orientation) ?? defaults.orientation
        favoritesOnly = try c.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? defaults.favoritesOnly
        shortsOnly = try c.decodeIfPresent(Bool.self, forKey: .shortsOnly) ?? defaults.shortsOnly
        shortsMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .shortsMaxSeconds) ?? defaults.shortsMaxSeconds
        latest = try c.decodeIfPresent(Bool.self, forKey: .latest) ?? defaults.latest
        maxBytes = try c.decodeIfPresent(Int64.self, forKey: .maxBytes) ?? defaults.maxBytes
    }
}

/// Turns the index plus the browse switches into the run of clips to play,
/// as library-relative original paths in play order.
public enum PlaylistBuilder {
    /// Narrow, then order — the desktop satellite's shape
    /// (`modes.py:build_satellite_playlist_paths`), minus the group collapse it
    /// does off the metadata sidecars, which Warm Gun has no index of yet.
    ///
    /// The two orders are not two flavours of the same thing. Shuffle is the
    /// watch-weighted draw: chronically skipped clips sit builds out and loved
    /// ones land early. Latest is a review order and carries no weighting at
    /// all, deliberately — a new arrival must surface however often it has been
    /// skipped away from before.
    ///
    /// Every draw comes off *rng*, so one seed is one playlist: the run is
    /// knowable in advance, which is what lets the prefetcher work both
    /// directions from the current clip.
    public static func build(catalog: Catalog, options: BrowseOptions, favoriteStems: Set<String>,
                             weird: Set<String>, stats: WatchStats,
                             rng: inout some RandomNumberGenerator) -> [String] {
        let clips = catalog.clips.filter { survivesFilters($0, options, favoriteStems, weird) }
        if options.latest {
            // Newest first; same-second arrivals fall back to their path, so the
            // order is total and a rebuild never reshuffles what did not change.
            return clips
                .sorted { $0.modified == $1.modified ? $0.path < $1.path : $0.modified > $1.modified }
                .map(\.path)
        }
        let survivors = clips.map(\.path).filter {
            Weighting.passesInclusion(weight: stats.weight(for: $0), rng: &rng)
        }
        return Weighting.weightedShuffle(survivors, weight: stats.weight(for:), rng: &rng)
    }

    /// The switches, all of which only ever narrow, so their order among
    /// themselves cannot matter. Favorites are matched by stem because that is
    /// all the desktop's `favs.csv` carries, and stems are unique library-wide.
    /// A clip whose duration the listing never reported cannot be shown to be
    /// short, so Shorts drops it rather than guessing.
    private static func survivesFilters(_ clip: Clip, _ options: BrowseOptions,
                                        _ favoriteStems: Set<String>, _ weird: Set<String>) -> Bool {
        clip.orientation == options.orientation
            && !weird.contains(clip.path)
            && clip.size <= options.maxBytes
            && (!options.favoritesOnly || favoriteStems.contains(clip.stem))
            && (!options.shortsOnly || (clip.duration ?? .infinity) <= options.shortsMaxSeconds)
    }
}
