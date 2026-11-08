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
