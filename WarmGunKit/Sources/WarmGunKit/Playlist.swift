import Foundation

/// The kinds of clip the controls sheet lets the browse narrow to. Every clip
/// is exactly one, and the desktop settles which: it records the kind on the
/// video's metadata sidecar (`video.type`), for the whole library, so the same
/// clip is the same kind in every app that reads it. The raw values are that
/// field's own words.
///
/// Everything after the record is a fallback for a clip the phone has no
/// sidecar for — the non-AI scenes and the genau loops, whose records the
/// index does not carry: the overlay's lanes first, then the source folder,
/// then a running time. They are how this app answered the question before the
/// field existed, kept only for where the field cannot reach.
public enum ClipType: String, Codable, CaseIterable, Sendable {
    case genauClip = "genau_clip"
    /// A scene carved out of a longer one. Which folders hold them — and what
    /// the checkbox is called — is library vocabulary, defined only by the
    /// overlay.
    case excerpt
    case short
    case fullLength = "full_length"

    public static func classify(_ clip: Clip, shortsMaxSeconds: Double,
                                recorded: String? = nil,
                                measuredSeconds: Double? = nil,
                                overlay: ContentOverlay = .empty) -> ClipType {
        if let recorded, let kind = ClipType(rawValue: recorded) { return kind }
        if let lane = overlay.lane(for: clip.path) { return lane.type }
        if clip.source.localizedCaseInsensitiveContains("genau") { return .genauClip }
        if clip.source == "non_AI" { return .fullLength }
        if let seconds = measuredSeconds ?? clip.duration {
            return seconds <= shortsMaxSeconds ? .short : .fullLength
        }
        // The real pCloud listing carries no durations at all, so until the
        // phone has measured a clip its size stands in: the originals run
        // near half a megabyte per second.
        let estimated = Double(clip.size) / estimatedBytesPerSecond
        return estimated <= shortsMaxSeconds ? .short : .fullLength
    }

    /// What a kind was called in a browse persisted before the desktop's
    /// vocabulary arrived. An app update must never cost the saved controls.
    static let retiredNames: [String: ClipType] = [
        "genau": .genauClip, "acts": .excerpt, "fullLength": .fullLength,
    ]

    private static let estimatedBytesPerSecond = 500_000.0
}

/// Every switch on the controls sheet, in one value.
///
/// A plain record with nothing derived in it, so the app can persist it and hand
/// it straight back on the next launch — and so a rebuild is a pure function of
/// this plus the index, with no network in it and nothing to invalidate.
public struct BrowseOptions: Codable, Equatable, Sendable {
    public var orientation: Orientation
    public var favoritesOnly: Bool
    public var types: Set<ClipType>
    public var shortsMaxSeconds: Double
    public var latest: Bool
    /// Act buttons the user switched OFF (overlay-defined labels); empty means
    /// everything shows. Stored as the disabled side so the default needs no
    /// knowledge of which buttons the overlay defines.
    public var disabledActs: Set<String>
    /// The size ceiling that keeps the legacy HEVC files sitting in the
    /// originals tree out: the phone fetches a clip whole before it plays, so an
    /// outlier is minutes of black screen rather than a slow start.
    public var maxBytes: Int64

    public init(orientation: Orientation = .portrait, favoritesOnly: Bool = false,
                types: Set<ClipType> = Set(ClipType.allCases), shortsMaxSeconds: Double = 10,
                latest: Bool = false, disabledActs: Set<String> = [], maxBytes: Int64 = 25_000_000) {
        self.orientation = orientation
        self.favoritesOnly = favoritesOnly
        self.types = types
        self.shortsMaxSeconds = shortsMaxSeconds
        self.latest = latest
        self.disabledActs = disabledActs
        self.maxBytes = maxBytes
    }

    private enum CodingKeys: String, CodingKey {
        case orientation, favoritesOnly, types, shortsOnly, shortsMaxSeconds, latest, disabledActs, maxBytes
    }

    /// A blob persisted before a switch existed decodes with that switch at its
    /// default — an app update must never cost the saved controls. The retired
    /// "shorts only" switch migrates into the type checkboxes it became.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrowseOptions()
        orientation = try c.decodeIfPresent(Orientation.self, forKey: .orientation) ?? defaults.orientation
        favoritesOnly = try c.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? defaults.favoritesOnly
        if let saved = try c.decodeIfPresent([String].self, forKey: .types) {
            types = Set(saved.compactMap { ClipType(rawValue: $0) ?? ClipType.retiredNames[$0] })
        } else if try c.decodeIfPresent(Bool.self, forKey: .shortsOnly) == true {
            types = [.short]
        } else {
            types = defaults.types
        }
        shortsMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .shortsMaxSeconds) ?? defaults.shortsMaxSeconds
        latest = try c.decodeIfPresent(Bool.self, forKey: .latest) ?? defaults.latest
        disabledActs = try c.decodeIfPresent(Set<String>.self, forKey: .disabledActs) ?? []
        maxBytes = try c.decodeIfPresent(Int64.self, forKey: .maxBytes) ?? defaults.maxBytes
    }

    /// The retired key never rides out again.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(favoritesOnly, forKey: .favoritesOnly)
        try c.encode(types, forKey: .types)
        try c.encode(shortsMaxSeconds, forKey: .shortsMaxSeconds)
        try c.encode(latest, forKey: .latest)
        try c.encode(disabledActs, forKey: .disabledActs)
        try c.encode(maxBytes, forKey: .maxBytes)
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
    /// ones land early, on the weight Evolver stamped from BOTH apps' viewing.
    /// Latest is a review order and carries no weighting at all, deliberately —
    /// a new arrival must surface however often it has been skipped away from
    /// before.
    ///
    /// Every draw comes off *rng*, so one seed is one playlist: the run is
    /// knowable in advance, which is what lets the prefetcher work both
    /// directions from the current clip.
    public static func build(catalog: Catalog, options: BrowseOptions, favoriteKeys: Set<String>,
                             weird: Set<String>, weights: WatchWeights,
                             measuredSeconds: [String: Double] = [:],
                             overlay: ContentOverlay = .empty,
                             acts: [String: String] = [:],
                             kinds: [String: String] = [:],
                             rng: inout some RandomNumberGenerator) -> [String] {
        let clips = catalog.clips.filter {
            survivesFilters($0, options, favoriteKeys, weird, kinds[$0.path],
                            measuredSeconds[$0.path], overlay, acts[$0.path])
        }
        if options.latest {
            // Newest first; same-second arrivals fall back to their path, so the
            // order is total and a rebuild never reshuffles what did not change.
            return clips
                .sorted { $0.modified == $1.modified ? $0.path < $1.path : $0.modified > $1.modified }
                .map(\.path)
        }
        let survivors = clips.map(\.path).filter {
            Weighting.passesInclusion(weight: weights.weight(for: $0), rng: &rng)
        }
        return Weighting.weightedShuffle(survivors, weight: weights.weight(for:), rng: &rng)
    }

    /// The switches, all of which only ever narrow, so their order among
    /// themselves cannot matter. Favorites are matched by the key their lane is
    /// filed under (`LibraryPaths.favoriteKey`).
    private static func survivesFilters(_ clip: Clip, _ options: BrowseOptions,
                                        _ favoriteKeys: Set<String>, _ weird: Set<String>,
                                        _ recorded: String?, _ measured: Double?,
                                        _ overlay: ContentOverlay, _ act: String?) -> Bool {
        let type = ClipType.classify(clip, shortsMaxSeconds: options.shortsMaxSeconds,
                                     recorded: recorded, measuredSeconds: measured, overlay: overlay)
        // A lane's orientation outranks the pixels; a genau loop has no
        // orientation of its own and plays whichever way the phone is held.
        let orientation = overlay.lane(for: clip.path)?.orientation ?? clip.orientation
        // The size ceiling exists to keep the legacy monsters out of the AI
        // originals; a real scene is big by nature and passes on principle.
        let gated = clip.path.hasPrefix("1_sorted/")
        // The combinable act buttons: a clip whose bucket is switched off hides.
        if let bucket = overlay.actBucket(for: act), options.disabledActs.contains(bucket) {
            return false
        }
        return (orientation == options.orientation || type == .genauClip)
            && !weird.contains(clip.path)
            && (!gated || clip.size <= options.maxBytes)
            && (!options.favoritesOnly || LibraryPaths.favoriteKey(forClip: clip.path).map(favoriteKeys.contains) == true)
            && options.types.contains(type)
    }
}
