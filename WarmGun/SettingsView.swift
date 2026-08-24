import SwiftUI
import WarmGunKit

/// The pCloud login, and nothing else: the library is found automatically,
/// the sync folder and cache run on their defaults, and every knob that used
/// to live here confused more than it configured.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var loggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if Keychain.token() == nil {
                        TextField("pCloud email", text: $username)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("pCloud password", text: $password)
                            .textContentType(.password)
                        if model.loginWantsCode {
                            TextField("Verification or recovery code", text: $verificationCode)
                                .textContentType(.oneTimeCode)
                            if model.tfaToken != nil {
                                Button("Send code by SMS") {
                                    Task { await model.sendTFACode(viaSMS: true) }
                                }
                                Button("Send code to your other pCloud apps") {
                                    Task { await model.sendTFACode(viaSMS: false) }
                                }
                                .disabled(!model.tfaHasDevices)
                            }
                        }
                        Button(loggingIn ? "Logging in…" : "Log in") {
                            loggingIn = true
                            Task {
                                // The password survives a failure for another
                                // try; only success clears it.
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
                        LabeledContent("pCloud", value: "logged in")
                        Button("Log out", role: .destructive) { model.logout() }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if username.isEmpty { username = model.settings.username }
                if password.isEmpty { password = Keychain.pendingPassword() ?? "" }
            }
        }
    }
}

/// Shown until there is a token; the same form, under a line saying why.
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
        case .failed(let message): return message
        default: return ""
        }
    }
}
