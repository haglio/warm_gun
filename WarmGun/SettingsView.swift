import SwiftUI

/// First-run setup and everything tunable: the pCloud login, the library
/// path, the sync folder, the cache and the prefetch window.
///
/// The password field is used for one login request and never stored; what is
/// kept is the token pCloud hands back, in the Keychain. Nothing typed here is
/// ever written into the repo's source — the library path in particular names
/// the machine's own tree.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var libraryPath = ""
    @State private var loggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                        TextField("API host", text: $model.settings.apiHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(loggingIn ? "Logging in…" : "Log in") {
                            loggingIn = true
                            Task {
                                // The password survives a failure for another
                                // try; only success clears it.
                                if await model.login(username: username, password: password, code: verificationCode) {
                                    password = ""
                                    verificationCode = ""
                                }
                                // On failure both fields keep their text — the
                                // next attempt costs only the code.
                                loggingIn = false
                            }
                        }
                        .disabled(loggingIn || username.isEmpty || password.isEmpty)
                        if let problem = model.lastProblem {
                            // Right under the button — the section at the very
                            // bottom of the form is below the fold on a phone,
                            // and an invisible error reads as nothing happening.
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } else {
                        LabeledContent("pCloud", value: "logged in")
                        Button("Log out", role: .destructive) { model.logout() }
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    TextField("/path/to/videos/videos/2D/AI", text: $libraryPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use this library") {
                        Task { await model.setLibraryPath(libraryPath) }
                    }
                    .disabled(libraryPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let catalog = model.catalog {
                        LabeledContent("Indexed", value: "\(catalog.clips.count) clips")
                    }
                    Button("Re-index now") { Task { await model.index() } }
                        .disabled(model.phase == .indexing || model.phase == .needsLogin)
                } header: {
                    Text("Library")
                }

                Section {
                    TextField("/WarmGun", text: $model.settings.syncFolder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Move weird clips to kinda_weird in pCloud", isOn: $model.settings.moveWeirdInCloud)
                    Button("Sync now") { Task { await model.syncWithCloud() } }
                        .disabled(model.phase == .needsLogin)
                } header: {
                    Text("Sharing with the desktop")
                }

                Section("Cache and prefetch") {
                    if let backlog = model.backlog {
                        LabeledContent("Downloading", value: "\(backlog.total - backlog.remaining) of \(backlog.total)")
                        Button("Stop downloading", role: .destructive) { model.cancelDownloadEverything() }
                    } else {
                        Button("Download this browse (\(model.session.playlist.count) clips)") {
                            model.downloadEverything()
                        }
                    }
                    LabeledContent("Cached", value: "\(model.cached.count) clips, \(model.cacheBytes / 1_000_000) MB")
                    Stepper("Cache cap: \(model.settings.cacheCapMB) MB", value: Binding(
                        get: { model.settings.cacheCapMB },
                        set: { model.update(cacheCapMB: $0) }), in: 256...16384, step: 256)
                    Stepper("Prefetch ahead: \(model.settings.prefetchAhead)", value: $model.settings.prefetchAhead, in: 2...60)
                    Stepper("Prefetch behind: \(model.settings.prefetchBehind)", value: $model.settings.prefetchBehind, in: 0...20)
                    Stepper("Skip files over \(model.settings.browse.maxBytes / 1_000_000) MB", value: Binding(
                        get: { Int(model.settings.browse.maxBytes / 1_000_000) },
                        set: { var b = model.settings.browse; b.maxBytes = Int64($0) * 1_000_000; model.update(browse: b) }), in: 5...1000, step: 5)
                    Stepper("Shorts are ≤ \(Int(model.settings.browse.shortsMaxSeconds)) s", value: Binding(
                        get: { Int(model.settings.browse.shortsMaxSeconds) },
                        set: { var b = model.settings.browse; b.shortsMaxSeconds = Double($0); model.update(browse: b) }), in: 1...120)
                    Button("Clear the cache", role: .destructive) { model.clearCache() }
                }

                if let problem = model.lastProblem {
                    Section("Last problem") { Text(problem).font(.footnote) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear {
                libraryPath = model.settings.libraryPath
                if username.isEmpty { username = model.settings.username }
                if password.isEmpty { password = Keychain.pendingPassword() ?? "" }
            }
        }
    }
}

/// Shown until there is a token and a library path; the same form, with a
/// line saying which of the two is missing.
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
        case .needsLibrary: return "Point Warm Gun at the library"
        case .failed(let message): return message
        default: return ""
        }
    }
}
