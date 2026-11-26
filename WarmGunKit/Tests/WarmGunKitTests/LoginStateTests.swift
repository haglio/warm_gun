import Testing
@testable import WarmGunKit

@Suite struct LoginStateTests {
    static let challenge = PCloudError(code: 2297, message: "TFA login required.",
                                       token: "tfa-tok-1", hasDevices: true)

    @Test func thePasswordLogsInUntilAChallengeHandsTheCodeATokenToGoWith() {
        var form = LoginState()
        #expect(form.attempt(code: "") == .password)
        #expect(form.attempt(code: " 123456 ") == .emailedCode("123456"))

        let shown = form.refused(by: Self.challenge, to: .password)
        #expect(shown == .say("pCloud wants a second factor. Enter a code from your authenticator app, or use a send button below."))
        #expect(form.wantsCode)
        #expect(form.challengeToken == "tfa-tok-1")
        #expect(form.canSendCodeToOtherApps)
        #expect(form.attempt(code: "123456")
                == .secondFactor(token: "tfa-tok-1", code: "123456", isRecovery: false))
        #expect(form.attempt(code: "abcd-efgh-ijkl-")
                == .secondFactor(token: "tfa-tok-1", code: "abcd-efgh-ijkl-", isRecovery: false))
        #expect(form.attempt(code: "abcd-efgh-ijkl-m")
                == .secondFactor(token: "tfa-tok-1", code: "abcd-efgh-ijkl-m", isRecovery: true))
        #expect(form.attempt(code: "") == .password)
    }
}

extension LoginStateTests {
    static let codeWanted = PCloudError(code: 1022, message: "Please provide 'code'.")

    @Test func aPasswordAskedForACodeHasPCloudEmailOneAndTheFieldWaitsForIt() {
        var form = LoginState()
        #expect(form.refused(by: Self.codeWanted, to: .password) == .emailCode)
        #expect(form.wantsCode && form.challengeToken == nil)
        #expect(LoginState.emailed(to: "gunner@example.test")
                == "pCloud emailed a verification code to gunner@example.test. Enter it below.")
    }

    @Test func aCodeStillAskedForIsOneItRefusedAndAnEmptyBoxEmailsAFreshOne() {
        var form = LoginState()
        _ = form.refused(by: Self.codeWanted, to: .password)
        let refusedCode = LoginState.Refusal.say(
            "pCloud refused that verification code. To have it email a new one, empty the code box and log in again.")
        #expect(form.refused(by: Self.codeWanted, to: .emailedCode("123456")) == refusedCode)
        #expect(form.refused(by: PCloudError(code: 2012, message: "Invalid code."), to: .emailedCode("1")) == refusedCode)
        #expect(form.wantsCode)
        #expect(form.attempt(code: "") == .password)
        #expect(form.refused(by: Self.codeWanted, to: .password) == .emailCode)
    }

    @Test func onlyABadCodeFromTheCodeCheckStopsTheLogin() {
        #expect(LoginState.stopsTheLogin(PCloudError(code: 2012, message: "Invalid code.")))
        #expect(LoginState.stopsTheLogin(PCloudError(code: 2092, message: "Invalid code.")))
        #expect(!LoginState.stopsTheLogin(Self.codeWanted))
        #expect(!LoginState.stopsTheLogin(PCloudError(code: 1000, message: "Log in required.")))
    }

    @Test func pCloudsEmailRequestCanAnswer2360AndStillHaveSentTheEmail() {
        #expect(LoginState.sentTheEmail(despite: PCloudError(code: 2360, message: "")))
        #expect(!LoginState.sentTheEmail(despite: PCloudError(code: 2000, message: "Log in failed.")))
    }

    @Test func anExpiredChallengeStartsOverAndAnythingElseIsJustSaid() {
        var form = LoginState()
        _ = form.refused(by: Self.challenge, to: .password)
        let expired = form.refused(by: PCloudError(code: 2064, message: "Expired."), to: .password)
        #expect(expired == .say("That code session expired — log in with the password again."))
        #expect(!form.wantsCode && form.challengeToken == nil)

        let before = form
        let other = form.refused(by: PCloudError(code: 2000, message: "Log in failed."), to: .password)
        #expect(other == .say("pCloud: Log in failed. (code 2000)"))
        #expect(form == before)
    }
}
