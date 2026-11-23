import SwiftUI
import WarmGunKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var loggingIn = false
    @State private var trying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if Keychain.token() == nil {
                        TextField("pCloud email", text: $username)
                            .textContentType(.username)
                            .emailEntry()
                            .autocorrectionDisabled()
                        SecureField("pCloud password", text: $password)
                            .textContentType(.password)
                        if model.loginForm.wantsCode {
                            TextField("Verification or recovery code", text: $verificationCode)
                                .textContentType(.oneTimeCode)
                            if model.loginForm.challengeToken != nil {
                                Button("Send code by SMS") {
                                    Task { await model.sendTFACode(viaSMS: true) }
                                }
                                Button("Send code to your other pCloud apps") {
                                    Task { await model.sendTFACode(viaSMS: false) }
                                }
                                .disabled(!model.loginForm.canSendCodeToOtherApps)
                            }
                        }
                        Button(loggingIn ? "Logging in…" : "Log in") {
                            loggingIn = true
                            Task {
                                if await model.login(username: username, password: password, code: verificationCode) {
                                    password = ""
                                    verificationCode = ""
                                }
                                loggingIn = false
                            }
                        }
                        .disabled(loggingIn || username.isEmpty || password.isEmpty)
                        if let problem = model.lastProblem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } else {
                        if let problem = model.lastProblem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        if model.phase == .failed || model.phase == .needsLibrary {
                            Button(trying ? "Trying again…" : "Try again") {
                                trying = true
                                Task {
                                    await model.tryAgain()
                                    trying = false
                                }
                            }
                            .disabled(trying)
                        }
                        LabeledContent("pCloud", value: "logged in")
                        Button("Log out", role: .destructive) { model.logout() }
                    }
                }
            }
            .navigationTitle("Settings")
            .inlineTitle()
            .onAppear {
                if username.isEmpty { username = model.settings.username }
                if password.isEmpty { password = Keychain.pendingPassword() ?? "" }
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.headline)
                .padding()
            SettingsView()
        }
    }

    private var headline: String {
        switch model.phase {
        case .needsLogin: return "Log in to pCloud to begin"
        case .needsLibrary: return "No library found in this pCloud account"
        case .failed: return "Couldn't read the library from pCloud — check the connection and try again"
        default: return ""
        }
    }
}
