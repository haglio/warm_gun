import Foundation

public struct LoginState: Equatable, Sendable {
    public enum Attempt: Equatable, Sendable {
        case password
        case emailedCode(String)
        case secondFactor(token: String, code: String, isRecovery: Bool)
    }

    public enum Refusal: Equatable, Sendable {
        case say(String)
        case emailCode
    }

    public private(set) var wantsCode = false
    public private(set) var challengeToken: String?
    public private(set) var canSendCodeToOtherApps = false

    public init() {}

    public func attempt(code: String) -> Attempt {
        let code = code.trimmingCharacters(in: .whitespaces)
        if code.isEmpty { return .password }
        if let challengeToken {
            return .secondFactor(token: challengeToken, code: code,
                                 isRecovery: code.count >= Self.shortestRecoveryCode)
        }
        return .emailedCode(code)
    }

    public mutating func refused(by error: PCloudError, to attempt: Attempt) -> Refusal {
        if let token = error.token {
            challengeToken = token
            canSendCodeToOtherApps = error.hasDevices ?? false
            wantsCode = true
            return .say("pCloud wants a second factor. Enter a code from your authenticator app, or use a send button below.")
        }
        if error.code == Self.codeWanted, attempt == .password {
            wantsCode = true
            return .emailCode
        }
        if error.code == Self.codeWanted || Self.badCodes.contains(error.code) {
            wantsCode = true
            return .say("pCloud refused that verification code. To have it email a new one, empty the code box and log in again.")
        }
        if error.code == Self.challengeExpired {
            challengeToken = nil
            wantsCode = false
            return .say("That code session expired — log in with the password again.")
        }
        return .say(error.localizedDescription)
    }

    public static func emailed(to email: String) -> String {
        "pCloud emailed a verification code to \(email). Enter it below."
    }

    public static func stopsTheLogin(_ codeCheck: PCloudError) -> Bool {
        badCodes.contains(codeCheck.code)
    }

    public static func sentTheEmail(despite answer: PCloudError) -> Bool {
        answer.code == Self.emailSentAnyway
    }

    public static let ranOut = "Your pCloud login ran out — log in again."

    private static let shortestRecoveryCode = 16
    private static let codeWanted = 1022
    private static let badCodes: Set<Int> = [2012, 2074, 2092]
    private static let challengeExpired = 2064
    private static let emailSentAnyway = 2360
}
