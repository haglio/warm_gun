import Foundation

public struct Sidecar: Codable, Equatable, Sendable {
    public struct Watch: Codable, Equatable, Sendable {
        public let weight: Double?

        public init(weight: Double?) {
            self.weight = weight
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let stamped = try? c.decodeIfPresent(Double.self, forKey: .weight)
            weight = (stamped?.isFinite == true && stamped! > 0) ? stamped : nil
        }
    }

    public let video: [String: String]?
    public let sourceImage: [String: String]?
    public let watch: Watch?
    public let favorite: Bool

    public var watchWeight: Double? { watch?.weight }

    enum CodingKeys: String, CodingKey {
        case video
        case sourceImage = "source_image"
        case watch
        case favorite
    }

    public init(video: [String: String]?, sourceImage: [String: String]?,
                watch: Watch? = nil, favorite: Bool = false) {
        self.video = video
        self.sourceImage = sourceImage
        self.watch = watch
        self.favorite = favorite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = Self.block(c, .video)
        sourceImage = Self.block(c, .sourceImage)
        watch = try? c.decodeIfPresent(Watch.self, forKey: .watch)
        favorite = ((try? c.decodeIfPresent(Bool.self, forKey: .favorite)) ?? nil) ?? false
    }

    private static func block(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: String]? {
        guard let fields = ((try? c.decodeIfPresent([String: Field].self, forKey: key)) ?? nil) else { return nil }
        return fields.compactMapValues(\.text)
    }

    private struct Field: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let string = try? c.decode(String.self) { text = string }
            else if let flag = try? c.decode(Bool.self) { text = flag ? "true" : "false" }
            else if let whole = try? c.decode(Int64.self) { text = String(whole) }
            else if let number = try? c.decode(Double.self) { text = String(number) }
            else { text = nil }
        }
    }
}

public struct GroupIndex: Sendable, Equatable {
    private var actionKeyByPath: [String: String] = [:]
    private var seedKeyByPath: [String: String] = [:]
    private var actionByPath: [String: String] = [:]
    private var typeByPath: [String: String] = [:]
    private var actionVideosByKey: [String: [String]] = [:]
    private var seedVideosByKey: [String: [String]] = [:]

    public var actionsByPath: [String: String] {
        actionByPath.filter { !$0.value.isEmpty }
    }

    public var typesByPath: [String: String] {
        typeByPath.filter { !$0.value.isEmpty }
    }

    public var isEmpty: Bool { actionByPath.isEmpty }

    public init(sidecars: [String: Sidecar]) {
        for (path, sidecar) in sidecars {
            actionByPath[path] = Self.normText(sidecar.video?["action"])
            typeByPath[path] = sidecar.video?["type"] ?? ""
            if let key = Self.actionGroupKey(sidecar) {
                actionKeyByPath[path] = key
                actionVideosByKey[key, default: []].append(path)
            }
            if let key = Self.seedGroupKey(sidecar) {
                seedKeyByPath[path] = key
                seedVideosByKey[key, default: []].append(path)
            }
        }
        for key in actionVideosByKey.keys { actionVideosByKey[key]?.sort() }
        for key in seedVideosByKey.keys { seedVideosByKey[key]?.sort() }
    }

    public func actionVideos(of path: String) -> [String] {
        guard let key = actionKeyByPath[path], let videos = actionVideosByKey[key],
              videos.count > 1 else { return [path] }
        return anchored(videos, on: path)
    }

    public func seedVideos(of path: String) -> [String] {
        guard let key = seedKeyByPath[path], let videos = seedVideosByKey[key] else { return [path] }
        let action = actionByPath[path] ?? ""
        let sameAction = videos.filter { (actionByPath[$0] ?? "") == action }
        guard sameAction.count > 1 else { return [path] }
        return anchored(sameAction, on: path)
    }

    public func group(_ mode: LoopMode, of path: String) -> [String]? {
        switch mode {
        case .seed: return seedVideos(of: path)
        case .action: return actionVideos(of: path)
        case .all, .single: return nil
        }
    }

    public func canLoop(_ mode: LoopMode, from path: String) -> Bool {
        group(mode, of: path).map { $0.count > 1 } ?? true
    }

    private func anchored(_ videos: [String], on path: String) -> [String] {
        guard let at = videos.firstIndex(of: path) else { return videos }
        return [path] + videos[..<at] + videos[(at + 1)...]
    }

    private static let imageIdentityFields = ["positive_prompt", "negative_prompt", "model",
                                              "resolution", "aspect_ratio", "quality", "style", "creativity", "seed"]
    private static let videoBaseFields = ["prompt", "model", "resolution", "aspect_ratio", "quality"]

    static func actionGroupKey(_ sidecar: Sidecar) -> String? {
        if let image = sidecar.sourceImage, !image.isEmpty {
            return fieldKey("img", image, imageIdentityFields)
        }
        guard let video = sidecar.video, !normText(video["prompt"]).isEmpty else { return nil }
        return fieldKey("t2v", video, videoBaseFields + ["seed"])
    }

    static func seedGroupKey(_ sidecar: Sidecar) -> String? {
        if let image = sidecar.sourceImage, !image.isEmpty {
            guard !normText(image["seed"]).isEmpty, !normText(image["positive_prompt"]).isEmpty else { return nil }
            return fieldKey("img", image, imageIdentityFields.filter { $0 != "seed" })
        }
        guard let video = sidecar.video,
              !normText(video["seed"]).isEmpty, !normText(video["prompt"]).isEmpty else { return nil }
        return fieldKey("t2v", video, videoBaseFields + ["action"])
    }

    private static func fieldKey(_ prefix: String, _ block: [String: String], _ fields: [String]) -> String {
        prefix + "|" + fields.map { normText(block[$0]) }.joined(separator: "|")
    }

    public static func normText(_ value: String?) -> String {
        (value ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
