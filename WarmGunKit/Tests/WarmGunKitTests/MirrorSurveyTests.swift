import Foundation
import Testing
@testable import WarmGunKit

@Suite struct MirrorSurveyTests {
    static let one = "1_sorted/alpha/portrait/clip-one.mp4"
    static let two = "1_sorted/beta/landscape/clip-two.mp4"
    static let oneSidecar = "2_outbox/upscaled_by_orientation/portrait/alpha/clip-one_topaz.json"
    static let twoSidecar = "2_outbox/upscaled_by_orientation/landscape/beta/clip-two_topaz.json"

    static func branch(_ listed: [String: Double]) -> SurveyedBranch {
        let files = listed.map { path, written in
            LibraryFile(path: path, fileID: 1, size: 100, modified: Date(timeIntervalSince1970: written),
                        duration: nil, videoCodec: nil, width: nil, height: nil)
        }
        return SurveyedBranch(path: "/mirror/2D/AI", files: files,
                              index: SidecarIndex(branch: .ai, clipPaths: [one, two], listing: Array(listed.keys)))
    }

    @Test func theFingerprintMovesWhenASidecarArrivesOrLeavesOrIsWrittenAgain() {
        let today = MirrorSurvey(branches: [Self.branch([Self.oneSidecar: 1_000, Self.twoSidecar: 2_000])])
        let again = MirrorSurvey(branches: [Self.branch([Self.twoSidecar: 2_000, Self.oneSidecar: 1_000])])
        let rewritten = MirrorSurvey(branches: [Self.branch([Self.oneSidecar: 3_000, Self.twoSidecar: 2_000])])
        let shrunk = MirrorSurvey(branches: [Self.branch([Self.twoSidecar: 2_000])])
        #expect(today.fingerprint == again.fingerprint)
        #expect(today.fingerprint != rewritten.fingerprint)
        #expect(today.fingerprint != shrunk.fingerprint)
    }

    @Test func aFetchSpeaksForTheMirrorOnlyWhenEverySidecarTheSurveyNamedCameBack() {
        let survey = MirrorSurvey(branches: [Self.branch([Self.oneSidecar: 1_000, Self.twoSidecar: 2_000])])
        let sidecar = Sidecar(video: ["action": "alpha"], sourceImage: nil)
        #expect(survey.isComplete([Self.one: sidecar, Self.two: sidecar]))
        #expect(!survey.isComplete([Self.one: sidecar]))
    }
}
