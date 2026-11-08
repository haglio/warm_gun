import Foundation

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

public struct MirrorSurvey: Sendable {
    public let branches: [SurveyedBranch]

    public init(branches: [SurveyedBranch]) {
        self.branches = branches
    }

    public var fingerprint: String {
        branches.map { branch in
            let newest = branch.files.map(\.modified.timeIntervalSince1970).max() ?? 0
            return "\(branch.index.videosByListedSidecar.count)|\(Int(newest))"
        }.joined(separator: ";")
    }

    public func isComplete(_ fetched: [String: Data]) -> Bool {
        branches.allSatisfy { branch in
            branch.index.videosByListedSidecar.values.allSatisfy { fetched[$0] != nil }
        }
    }
}
