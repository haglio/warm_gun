import Testing
@testable import WarmGunKit

@Suite struct LoginStateTests {
    static let challenge = PCloudError(code: 2297, message: "TFA login required.",
                                       token: "tfa-tok-1", hasDevices: true)

    @Test func thePasswordLogsInUntilAChallengeHandsTheCodeATokenToGoWith() {
        var form = LoginState()
        #expect(form.attempt(code: "") == .password(code: nil))
        #expect(form.attempt(code: " 123456 ") == .password(code: "123456"))

        let shown = form.refused(by: Self.challenge)
        #expect(shown == "pCloud wants a second factor. Enter a code from your authenticator app, or use a send button below.")
        #expect(form.wantsCode)
        #expect(form.challengeToken == "tfa-tok-1")
        #expect(form.canSendCodeToOtherApps)
        #expect(form.attempt(code: "123456")
                == .secondFactor(token: "tfa-tok-1", code: "123456", isRecovery: false))
        #expect(form.attempt(code: "abcd-efgh-ijkl-")
                == .secondFactor(token: "tfa-tok-1", code: "abcd-efgh-ijkl-", isRecovery: false))
        #expect(form.attempt(code: "abcd-efgh-ijkl-m")
                == .secondFactor(token: "tfa-tok-1", code: "abcd-efgh-ijkl-m", isRecovery: true))
        #expect(form.attempt(code: "") == .password(code: nil))
    }
}

extension LoginStateTests {
    @Test func aCodeAskedForOrRefusedShowsTheFieldAnExpiredChallengeStartsOverAndAnythingElseIsJustSaid() {
        var form = LoginState()
        let asked = form.refused(by: PCloudError(code: 1022, message: "Please provide 'code'."))
        #expect(asked == "This account wants a verification code — check your authenticator app (or email/SMS from pCloud) and enter it below.")
        #expect(form.wantsCode && form.challengeToken == nil)
        let wrong = form.refused(by: PCloudError(code: 2012, message: "Invalid code."))
        #expect(wrong == "pCloud refused that verification code — try a fresh one.")
        #expect(form.wantsCode)

        _ = form.refused(by: Self.challenge)
        let expired = form.refused(by: PCloudError(code: 2064, message: "Expired."))
        #expect(expired == "That code session expired — log in with the password again.")
        #expect(!form.wantsCode && form.challengeToken == nil)

        let before = form
        let other = form.refused(by: PCloudError(code: 2000, message: "Log in failed."))
        #expect(other == "pCloud: Log in failed. (code 2000)")
        #expect(form == before)
    }
}
