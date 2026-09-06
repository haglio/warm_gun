import Foundation

/// One clip's metadata sidecar, as the pipeline writes it: a `video` block
/// (always), a `source_image` block (image-to-video clips), and — since
/// Evolver's Watch Weights stage — a `watch` block and a `favorite` flag. The
/// blocks are read as dictionaries of text, whatever JSON shape each field
/// arrived in, because the desktop reads them through `str(value or "")` and
/// writes some of them as numbers.
public struct Sidecar: Codable, Equatable, Sendable {
    /// The `watch` block Evolver stamps on every library video: what both apps
    /// completed, skipped and locked, summed, and the playback weight that sum
    /// earns. Only the weight is read here. The formula lives on the desktop
    /// (`evolver/util/watch.py`) so that one implementation serves every app,
    /// and this side never recomputes it — it reads the number or nothing.
    public struct Watch: Codable, Equatable, Sendable {
        public let weight: Double?

        public init(weight: Double?) {
            self.weight = weight
        }

        /// A weight that could not serve as a multiplier is no weight at all.
        /// Zero would silence a clip for good and a negative one would sort it
        /// FIRST in the draw — the exact inverse of what the number means — so
        /// only a finite positive number counts as stamped.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let stamped = try? c.decodeIfPresent(Double.self, forKey: .weight)
            weight = (stamped?.isFinite == true && stamped! > 0) ? stamped : nil
        }
    }

    public let video: [String: String]?
    public let sourceImage: [String: String]?
    public let watch: Watch?
    /// Whether the desktop's favorites hold this clip. Evolver writes the field
    /// only when it is true, and the file it mirrors already carries the
    /// favorites made on the phone, so this is both sides' answer.
    public let favorite: Bool

    /// The stamped weight, or nil when the sidecar carries none — which the
    /// draw reads as the neutral 1.0.
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

    /// A block this side cannot read costs only itself. The sidecar carries the
    /// act the loops group by as well as the weight, and a `watch` written in a
    /// shape not expected here must not take the act down with it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = Self.block(c, .video)
        sourceImage = Self.block(c, .sourceImage)
        watch = try? c.decodeIfPresent(Watch.self, forKey: .watch)
        favorite = ((try? c.decodeIfPresent(Bool.self, forKey: .favorite)) ?? nil) ?? false
    }

    /// One block, read the way the desktop reads it.
    ///
    /// The pipeline does not keep these fields all strings — the Video Kinds
    /// stage writes `video.duration_seconds` as a JSON float beside
    /// `video.type` (`evolver/util/video_type.py`) — while the desktop reads
    /// every field through `str(value or "")` and never notices. Decoded as
    /// `[String: String]` a single number cost the WHOLE sidecar, and with it
    /// the act, the weight and the flag. So a scalar of any kind is taken and
    /// spelled the way that call would spell it, and anything that is not a
    /// scalar is left out: no field a group key is built from is ever one, and
    /// an absent key already stands for the empty string.
    private static func block(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: String]? {
        guard let fields = ((try? c.decodeIfPresent([String: Field].self, forKey: key)) ?? nil) else { return nil }
        return fields.compactMapValues(\.text)
    }

    /// One field of a block, whatever shape it arrived in.
    private struct Field: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let string = try? c.decode(String.self) { text = string }
            else if let flag = try? c.decode(Bool.self) { text = flag ? "true" : "false" }
            // Whole before fractional, so a seed written as an integer reads
            // back as one — `12345`, never `12345.0`, which would not match the
            // key the desktop built from the same value. The cost is that a
            // FLOAT that happens to be whole reads back without its `.0`, where
            // Python's `str` would keep it; that is only `duration_seconds`,
            // which no group key is built from, and telling the two apart would
            // mean reading the raw JSON text this API does not expose.
            else if let whole = try? c.decode(Int64.self) { text = String(whole) }
            else if let number = try? c.decode(Double.self) { text = String(number) }
            else { text = nil }
        }
    }
}

/// The desktop's grouping, ported field for field from
/// `fun_time/media_metadata.py`. Two orthogonal axes over the generation
/// parameters: an ACTION group keys on everything INCLUDING the seed (one
/// subject, its different acts); a SEED family keys on everything EXCLUDING
/// the seed — plus the act, for text-to-video — (one act, its different
/// subjects). `created` never joins a key.
public struct GroupIndex: Sendable, Equatable {
    private var actionKeyByPath: [String: String] = [:]
    private var seedKeyByPath: [String: String] = [:]
    private var actByPath: [String: String] = [:]
    private var kindByPath: [String: String] = [:]
    private var actionClipsByKey: [String: [String]] = [:]
    private var seedClipsByKey: [String: [String]] = [:]

    /// Every clip's normalized recorded act, for the build's act buttons.
    public var actsByPath: [String: String] {
        actByPath.filter { !$0.value.isEmpty }
    }

    /// Every clip's recorded kind — what the desktop wrote in `video.type`,
    /// which is what the type checkboxes narrow by wherever it is there.
    public var kindsByPath: [String: String] {
        kindByPath.filter { !$0.value.isEmpty }
    }

    /// True until any sidecar has been indexed — the UI's cue that the loops
    /// have nothing to stand on yet.
    public var isEmpty: Bool { actByPath.isEmpty }

    public init(sidecars: [String: Sidecar]) {
        for (path, sidecar) in sidecars {
            actByPath[path] = Self.normText(sidecar.video?["action"])
            kindByPath[path] = sidecar.video?["type"] ?? ""
            if let key = Self.actionGroupKey(sidecar) {
                actionKeyByPath[path] = key
                actionClipsByKey[key, default: []].append(path)
            }
            if let key = Self.seedGroupKey(sidecar) {
                seedKeyByPath[path] = key
                seedClipsByKey[key, default: []].append(path)
            }
        }
        for key in actionClipsByKey.keys { actionClipsByKey[key]?.sort() }
        for key in seedClipsByKey.keys { seedClipsByKey[key]?.sort() }
    }

    /// The clip's subject doing its different things — always anchored first,
    /// and never empty: a clip in no group is a group of itself.
    public func actionClips(of path: String) -> [String] {
        guard let key = actionKeyByPath[path], let clips = actionClipsByKey[key],
              clips.count > 1 else { return [path] }
        return anchored(clips, on: path)
    }

    /// The clip's act done by its different subjects: the family narrowed to
    /// the anchor's own act (normalized, so casing variants share a row) —
    /// the narrowing the desktop applies in `seed_family_items`.
    public func seedClips(of path: String) -> [String] {
        guard let key = seedKeyByPath[path], let clips = seedClipsByKey[key] else { return [path] }
        let act = actByPath[path] ?? ""
        let sameAct = clips.filter { (actByPath[$0] ?? "") == act }
        guard sameAct.count > 1 else { return [path] }
        return anchored(sameAct, on: path)
    }

    private func anchored(_ clips: [String], on path: String) -> [String] {
        guard let at = clips.firstIndex(of: path) else { return clips }
        return [path] + clips[..<at] + clips[(at + 1)...]
    }

    // MARK: - the keys, verbatim from the desktop

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

    /// `" ".join(str(value or "").split()).lower()` — whitespace collapsed,
    /// lowercased, nil to empty.
    public static func normText(_ value: String?) -> String {
        (value ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
