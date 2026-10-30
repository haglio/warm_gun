import Foundation

/// Where a pCloud login stands between one press of Log in and the next.
public struct LoginState: Equatable, Sendable {
    public enum Attempt: Equatable, Sendable {
        case password(code: String?)
        case secondFactor(token: String, code: String, isRecovery: Bool)
    }

    public private(set) var wantsCode = false
    public private(set) var challengeToken: String?
    public private(set) var canSendCodeToOtherApps = false

    public init() {}

    public func attempt(code: String) -> Attempt {
        let code = code.trimmingCharacters(in: .whitespaces)
        if let challengeToken, !code.isEmpty {
            return .secondFactor(token: challengeToken, code: code,
                                 isRecovery: code.count >= Self.shortestRecoveryCode)
        }
        return .password(code: code.isEmpty ? nil : code)
    }

    public mutating func refused(by error: PCloudError) -> String {
        if let token = error.token {
            challengeToken = token
            canSendCodeToOtherApps = error.hasDevices ?? false
            wantsCode = true
            return "pCloud wants a second factor. Enter a code from your authenticator app, or use a send button below."
        }
        switch error.code {
        case Self.codeWanted:
            wantsCode = true
            return "This account wants a verification code — check your authenticator app (or email/SMS from pCloud) and enter it below."
        case Self.codeRefused:
            wantsCode = true
            return "pCloud refused that verification code — try a fresh one."
        case Self.challengeExpired:
            challengeToken = nil
            wantsCode = false
            return "That code session expired — log in with the password again."
        default:
            return error.localizedDescription
        }
    }

    private static let shortestRecoveryCode = 16
    private static let codeWanted = 1022
    private static let codeRefused = 2012
    private static let challengeExpired = 2064
}
