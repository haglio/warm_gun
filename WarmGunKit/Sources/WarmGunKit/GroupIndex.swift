import Foundation

/// One clip's metadata sidecar, as the pipeline writes it: a `video` block
/// (always) and a `source_image` block (image-to-video clips). Every value on
/// disk is a string, so the blocks decode as plain dictionaries.
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
        video = try c.decodeIfPresent([String: String].self, forKey: .video)
        sourceImage = try c.decodeIfPresent([String: String].self, forKey: .sourceImage)
        watch = try? c.decodeIfPresent(Watch.self, forKey: .watch)
        favorite = ((try? c.decodeIfPresent(Bool.self, forKey: .favorite)) ?? nil) ?? false
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
    private var actionMembersByKey: [String: [String]] = [:]
    private var seedMembersByKey: [String: [String]] = [:]

    /// Every clip's normalized recorded act, for the build's act-query filter.
    public var actsByPath: [String: String] {
        actByPath.filter { !$0.value.isEmpty }
    }

    /// True until any sidecar has been indexed — the UI's cue that the loops
    /// have nothing to stand on yet.
    public var isEmpty: Bool { actByPath.isEmpty }

    public init(sidecars: [String: Sidecar]) {
        for (path, sidecar) in sidecars {
            actByPath[path] = Self.normText(sidecar.video?["action"])
            if let key = Self.actionGroupKey(sidecar) {
                actionKeyByPath[path] = key
                actionMembersByKey[key, default: []].append(path)
            }
            if let key = Self.seedGroupKey(sidecar) {
                seedKeyByPath[path] = key
                seedMembersByKey[key, default: []].append(path)
            }
        }
        for key in actionMembersByKey.keys { actionMembersByKey[key]?.sort() }
        for key in seedMembersByKey.keys { seedMembersByKey[key]?.sort() }
    }

    /// The clip's subject doing its different things — always anchored first,
    /// and never empty: a clip in no group is a group of itself.
    public func actionMembers(of path: String) -> [String] {
        guard let key = actionKeyByPath[path], let members = actionMembersByKey[key],
              members.count > 1 else { return [path] }
        return anchored(members, on: path)
    }

    /// The clip's act done by its different subjects: the family narrowed to
    /// the anchor's own act (normalized, so casing variants share a row) —
    /// the narrowing the desktop applies in `seed_family_members`.
    public func seedMembers(of path: String) -> [String] {
        guard let key = seedKeyByPath[path], let members = seedMembersByKey[key] else { return [path] }
        let act = actByPath[path] ?? ""
        let sameAct = members.filter { (actByPath[$0] ?? "") == act }
        guard sameAct.count > 1 else { return [path] }
        return anchored(sameAct, on: path)
    }

    private func anchored(_ members: [String], on path: String) -> [String] {
        guard let at = members.firstIndex(of: path) else { return members }
        return [path] + members[..<at] + members[(at + 1)...]
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
