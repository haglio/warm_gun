import Foundation

/// One clip's metadata sidecar, as the pipeline writes it: a `video` block
/// (always) and a `source_image` block (image-to-video clips). Every value on
/// disk is a string, so the blocks decode as plain dictionaries.
public struct Sidecar: Codable, Equatable, Sendable {
    public let video: [String: String]?
    public let sourceImage: [String: String]?

    enum CodingKeys: String, CodingKey {
        case video
        case sourceImage = "source_image"
    }

    public init(video: [String: String]?, sourceImage: [String: String]?) {
        self.video = video
        self.sourceImage = sourceImage
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
