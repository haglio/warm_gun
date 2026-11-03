import Foundation

public enum VideoType: String, Codable, CaseIterable, Sendable {
    case genauFlick = "genau_flick"
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
        let estimated = Double(video.size) / estimatedBytesPerSecond
        return estimated <= shortsMaxSeconds ? .short : .fullLength
    }

    static let retiredNames: [String: VideoType] = [
        "genau": .genauFlick, "genau_clip": .genauFlick, "acts": .excerpt, "fullLength": .fullLength,
    ]

    init?(named name: String) {
        guard let type = VideoType(rawValue: name) ?? Self.retiredNames[name] else { return nil }
        self = type
    }

    private static let estimatedBytesPerSecond = 500_000.0
}

public struct Filters: Codable, Equatable, Sendable {
    public var shape: VideoShape
    public var favoritesOnly: Bool
    public var types: Set<VideoType>
    public var shortsMaxSeconds: Double
    public var latest: Bool
    public var disabledActions: Set<String>
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

public enum PlaylistBuilder {
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

    private static func survivesFilters(_ video: Video, _ options: Filters,
                                        _ favoriteKeys: Set<String>, _ trash: Set<String>,
                                        _ recorded: String?, _ measured: Double?,
                                        _ overlay: ContentOverlay, _ action: String?) -> Bool {
        let type = VideoType.classify(video, shortsMaxSeconds: options.shortsMaxSeconds,
                                     recorded: recorded, measuredSeconds: measured, overlay: overlay)
        let gated = video.path.hasPrefix("1_sorted/")
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
