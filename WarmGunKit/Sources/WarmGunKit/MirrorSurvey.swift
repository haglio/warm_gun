import Foundation

/// One branch of the metadata mirror as a launch's survey listed it: where it
/// is, what it holds, and which of that speaks for a clip the app can play.
public struct SurveyedBranch: Sendable {
    public let path: String
    public let files: [LibraryFile]
    public let index: SidecarIndex

    public init(path: String, files: [LibraryFile], index: SidecarIndex) {
        self.path = path
        self.files = files
        self.index = index
    }
}

/// What one cheap listing per branch says about the whole mirror.
public struct MirrorSurvey: Sendable {
    public let branches: [SurveyedBranch]

    public init(branches: [SurveyedBranch]) {
        self.branches = branches
    }

    /// How many sidecars each branch holds that are worth having, and the
    /// newest write among everything it lists.
    public var fingerprint: String {
        branches.map { branch in
            let newest = branch.files.map(\.modified.timeIntervalSince1970).max() ?? 0
            return "\(branch.index.clipsByListedSidecar.count)|\(Int(newest))"
        }.joined(separator: ";")
    }

    /// Whether *fetched* holds every sidecar the survey named: only then does
    /// the corpus on the device speak for the mirror as the survey found it.
    public func isComplete(_ fetched: [String: Sidecar]) -> Bool {
        branches.allSatisfy { branch in
            branch.index.clipsByListedSidecar.values.allSatisfy { fetched[$0] != nil }
        }
    }
}
