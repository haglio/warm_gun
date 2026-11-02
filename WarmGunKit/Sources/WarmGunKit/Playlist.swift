import Foundation

/// The types of video the type buttons let the filters narrow to. Every video
/// is exactly one, and the desktop settles which: it records the type on the
/// video's metadata sidecar (`video.type`), for the whole library, so the same
/// video is the same type in every app that reads it. The raw values are that
/// field's own words.
///
/// Everything after the record is a fallback for a video the phone has no
/// sidecar for — the non-AI scenes and Genau's flicks, whose records the
/// index does not carry: the overlay's lanes first, then the source folder,
/// then a running time. They are how this app answered the question before the
/// field existed, kept only for where the field cannot reach.
public enum VideoType: String, Codable, CaseIterable, Sendable {
    case genauFlick = "genau_flick"
    /// A scene carved out of a longer one. Which folders hold them is library
    /// vocabulary, defined only by the overlay.
    case excerpt
    case short
    case fullLength = "full_length"

    public static let clips: Set<VideoType> = [.short, .excerpt]

    public static func classify(_ video: Video, shortsMaxSeconds: Double,
                                recorded: String? = nil,
                                measuredSeconds: Double? = nil,
                                overlay: ContentOverlay = .empty) -> VideoType {
        if let recorded, let type = VideoType(named: recorded) { return type }
        if let lane = overlay.lane(for: video.path) { return lane.type }
        if video.source.localizedCaseInsensitiveContains("genau") { return .genauFlick }
        if video.source == "non_AI" { return .fullLength }
        if let seconds = measuredSeconds ?? video.duration {
            return seconds <= shortsMaxSeconds ? .short : .fullLength
        }
        // The real pCloud listing carries no durations at all, so until the
        // phone has measured a video its size stands in: the originals run
        // near half a megabyte per second.
        let estimated = Double(video.size) / estimatedBytesPerSecond
        return estimated <= shortsMaxSeconds ? .short : .fullLength
    }

    /// What a type was called in a filters persisted before the desktop's
    /// vocabulary arrived, and in a sidecar recorded before Genau's clips were
    /// called flicks. An app update must never cost the saved controls.
    static let retiredNames: [String: VideoType] = [
        "genau": .genauFlick, "genau_clip": .genauFlick, "acts": .excerpt, "fullLength": .fullLength,
    ]

    init?(named name: String) {
        guard let type = VideoType(rawValue: name) ?? Self.retiredNames[name] else { return nil }
        self = type
    }

    private static let estimatedBytesPerSecond = 500_000.0
}

/// Every filter on the controls, in one value.
///
/// A plain record with nothing derived in it, so the app can persist it and hand
/// it straight back on the next launch — and so a rebuild is a pure function of
/// this plus the index, with no network in it and nothing to invalidate.
public struct Filters: Codable, Equatable, Sendable {
    public var shape: VideoShape
    public var favoritesOnly: Bool
    public var types: Set<VideoType>
    public var shortsMaxSeconds: Double
    public var latest: Bool
    /// Action buttons the user switched OFF (overlay-defined labels); empty means
    /// everything shows. Stored as the disabled side so the default needs no
    /// knowledge of which buttons the overlay defines.
    public var disabledActions: Set<String>
    /// The size ceiling that keeps out the legacy HEVC upscales sitting in the
    /// originals tree.
    public var maxBytes: Int64

    public init(shape: VideoShape = .portrait, favoritesOnly: Bool = false,
                types: Set<VideoType> = Set(VideoType.allCases), shortsMaxSeconds: Double = 10,
                latest: Bool = false, disabledActions: Set<String> = [], maxBytes: Int64 = 25_000_000) {
        self.shape = shape
        self.favoritesOnly = favoritesOnly
        self.types = types
        self.shortsMaxSeconds = shortsMaxSeconds
        self.latest = latest
        self.disabledActions = disabledActions
        self.maxBytes = maxBytes
    }

    private enum CodingKeys: String, CodingKey {
        case shape = "orientation"
        case favoritesOnly, types, shortsOnly, shortsMaxSeconds, latest, maxBytes
        case disabledActions = "disabledActs"
    }

    /// A blob persisted before a switch existed decodes with that switch at its
    /// default — an app update must never cost the saved controls. The retired
    /// "shorts only" switch migrates into the types it became.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Filters()
        shape = try c.decodeIfPresent(VideoShape.self, forKey: .shape) ?? defaults.shape
        favoritesOnly = try c.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? defaults.favoritesOnly
        if let saved = try c.decodeIfPresent([String].self, forKey: .types) {
            types = Set(saved.compactMap(VideoType.init(named:)))
        } else if try c.decodeIfPresent(Bool.self, forKey: .shortsOnly) == true {
            types = [.short]
        } else {
            types = defaults.types
        }
        shortsMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .shortsMaxSeconds) ?? defaults.shortsMaxSeconds
        latest = try c.decodeIfPresent(Bool.self, forKey: .latest) ?? defaults.latest
        disabledActions = try c.decodeIfPresent(Set<String>.self, forKey: .disabledActions) ?? []
        maxBytes = try c.decodeIfPresent(Int64.self, forKey: .maxBytes) ?? defaults.maxBytes
    }

    /// The retired key never rides out again.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shape, forKey: .shape)
        try c.encode(favoritesOnly, forKey: .favoritesOnly)
        try c.encode(types, forKey: .types)
        try c.encode(shortsMaxSeconds, forKey: .shortsMaxSeconds)
        try c.encode(latest, forKey: .latest)
        try c.encode(disabledActions, forKey: .disabledActions)
        try c.encode(maxBytes, forKey: .maxBytes)
    }

    public func includes(_ wanted: Set<VideoType>) -> Bool {
        types.isSuperset(of: wanted)
    }

    public mutating func setIncluded(_ wanted: Set<VideoType>, _ included: Bool) {
        if included {
            types.formUnion(wanted)
        } else {
            types.subtract(wanted)
        }
    }
}

/// Turns the index plus the filters switches into the run of videos to play,
/// as library-relative original paths in play order.
public enum PlaylistBuilder {
    /// Narrow, then order — the desktop satellite's shape
    /// (`modes.py:build_satellite_playlist_paths`), minus the group collapse it
    /// does off the metadata sidecars.
    ///
    /// The two orders are not two flavors of the same thing. Shuffle is the
    /// watch-weighted draw: chronically skipped videos sit builds out and loved
    /// ones land early, on the weight Evolver stamped from BOTH apps' viewing.
    /// Latest is a review order and carries no weighting at all, deliberately —
    /// a new arrival must surface however often it has been skipped away from
    /// before.
    ///
    /// Every draw comes off *rng*, so one seed is one playlist: the run is
    /// knowable in advance, which is what lets the prefetcher work both
    /// directions from the current video.
    public static func build(catalog: Catalog, options: Filters, favoriteKeys: Set<String>,
                             trash: Set<String>, weights: WatchWeights,
                             measuredSeconds: [String: Double] = [:],
                             overlay: ContentOverlay = .empty,
                             actions: [String: String] = [:],
                             recordedTypes: [String: String] = [:],
                             rng: inout some RandomNumberGenerator) -> [String] {
        let videos = catalog.videos.filter {
            survivesFilters($0, options, favoriteKeys, trash, recordedTypes[$0.path],
                            measuredSeconds[$0.path], overlay, actions[$0.path])
        }
        if options.latest {
            // Newest first; same-second arrivals fall back to their path, so the
            // order is total and a rebuild never reshuffles what did not change.
            return videos
                .sorted { $0.modified == $1.modified ? $0.path < $1.path : $0.modified > $1.modified }
                .map(\.path)
        }
        let survivors = videos.map(\.path).filter {
            Weighting.passesInclusion(weight: weights.weight(for: $0), rng: &rng)
        }
        return Weighting.weightedShuffle(survivors, weight: weights.weight(for:), rng: &rng)
    }

    public static func playsInShape(_ video: Video, options: Filters, recorded: String? = nil,
                                          measuredSeconds: Double? = nil,
                                          overlay: ContentOverlay = .empty) -> Bool {
        let type = VideoType.classify(video, shortsMaxSeconds: options.shortsMaxSeconds,
                                     recorded: recorded, measuredSeconds: measuredSeconds, overlay: overlay)
        return fitsShape(video, type, options, overlay)
    }

    private static func fitsShape(_ video: Video, _ type: VideoType, _ options: Filters,
                                        _ overlay: ContentOverlay) -> Bool {
        type == .genauFlick || (overlay.lane(for: video.path)?.shape ?? video.shape) == options.shape
    }

    /// The switches, all of which only ever narrow, so their order among
    /// themselves cannot matter. Favorites are matched by the key their lane is
    /// filed under (`LibraryPaths.favoriteKey`).
    private static func survivesFilters(_ video: Video, _ options: Filters,
                                        _ favoriteKeys: Set<String>, _ trash: Set<String>,
                                        _ recorded: String?, _ measured: Double?,
                                        _ overlay: ContentOverlay, _ action: String?) -> Bool {
        let type = VideoType.classify(video, shortsMaxSeconds: options.shortsMaxSeconds,
                                     recorded: recorded, measuredSeconds: measured, overlay: overlay)
        // The size ceiling exists to keep the legacy monsters out of the AI
        // originals; a real scene is big by nature and passes on principle.
        let gated = video.path.hasPrefix("1_sorted/")
        // The combinable action buttons: a video whose bucket is switched off hides.
        if let bucket = overlay.actionBucket(for: action), options.disabledActions.contains(bucket) {
            return false
        }
        return fitsShape(video, type, options, overlay)
            && !trash.contains(video.path)
            && (!gated || video.size <= options.maxBytes)
            && (!options.favoritesOnly || LibraryPaths.favoriteKey(forVideo: video.path).map(favoriteKeys.contains) == true)
            && options.types.contains(type)
    }
}
