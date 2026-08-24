import WarmGunKit
import SwiftUI

/// What a double tap in the middle brings up: the browse switches, a line of
/// status, and the way to Settings.
struct ControlsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Browse") {
                    Toggle("Landscape library", isOn: binding(\.orientation, on: .landscape, off: .portrait))
                    Toggle("F-mode — favorites only", isOn: binding(\.favoritesOnly))
                    Toggle("Shorts only (≤ \(Int(model.settings.browse.shortsMaxSeconds)) s)", isOn: binding(\.shortsOnly))
                    Toggle("Latest first (else shuffle)", isOn: binding(\.latest))
                    Toggle("Loop each clip", isOn: Binding(
                        get: { model.settings.loopClip },
                        set: { model.update(loopClip: $0) }))
                }
                Section("Now") {
                    LabeledContent("Clip", value: "\(model.session.playlist.isEmpty ? 0 : model.session.index + 1) of \(model.session.playlist.count)")
                    LabeledContent("Locked", value: model.session.locked ? "yes" : "no")
                    LabeledContent("Favorite", value: model.session.current.map { model.favorites.contains(path: $0) ? "★" : "—" } ?? "—")
                    LabeledContent("Cached", value: "\(model.cached.count) clips, \(megabytes(model.cacheBytes)) MB")
                    if let backlog = model.backlog {
                        LabeledContent("Downloading", value: "\(backlog.total - backlog.remaining) of \(backlog.total)")
                        Button("Stop downloading", role: .destructive) { model.cancelDownloadEverything() }
                    } else {
                        Button("Download this browse (\(model.session.playlist.count) clips, \(megabytes(browseBytes)) MB)") {
                            model.downloadEverything()
                        }
                    }
                    if let problem = model.lastProblem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Settings") { showingSettings = true }
                }
            }
            .navigationTitle("Warm Gun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private var browseBytes: Int64 {
        guard let catalog = model.catalog else { return 0 }
        let wanted = Set(model.session.playlist)
        return catalog.clips.filter { wanted.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.0f", Double(bytes) / 1_000_000)
    }

    private func binding(_ key: WritableKeyPath<BrowseOptions, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.browse[keyPath: key] },
                set: { value in
                    var browse = model.settings.browse
                    browse[keyPath: key] = value
                    model.update(browse: browse)
                })
    }

    private func binding(_ key: WritableKeyPath<BrowseOptions, Orientation>, on: Orientation, off: Orientation) -> Binding<Bool> {
        Binding(get: { model.settings.browse[keyPath: key] == on },
                set: { value in
                    var browse = model.settings.browse
                    browse[keyPath: key] = value ? on : off
                    model.update(browse: browse)
                })
    }
}
