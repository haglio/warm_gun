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
                Section {
                    Toggle("Genau clips", isOn: typeBinding(.genau))
                    Toggle("Shorts", isOn: typeBinding(.short))
                    if let actsLabel = model.overlay.actsLabel {
                        Toggle(actsLabel, isOn: typeBinding(.acts))
                    }
                    Toggle("Full length", isOn: typeBinding(.fullLength))
                } header: {
                    Text("Types")
                }
                Section("Order") {
                    Picker("Order", selection: binding(\.latest)) {
                        Text("Shuffle").tag(false)
                        Text("Latest").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Loop", selection: Binding(
                        get: { model.loopMode },
                        set: { model.setLoop($0) })) {
                        Text("All").tag(AppModel.LoopMode.all)
                        Text("1").tag(AppModel.LoopMode.single)
                        Text("Seed").tag(AppModel.LoopMode.seed)
                        Text("Action").tag(AppModel.LoopMode.action)
                    }
                    .pickerStyle(.segmented)
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

    private func binding(_ key: WritableKeyPath<BrowseOptions, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.browse[keyPath: key] },
                set: { value in
                    var browse = model.settings.browse
                    browse[keyPath: key] = value
                    model.update(browse: browse)
                })
    }

    /// A type's checkbox: membership in the browse's type set. Unchecking the
    /// last one would mean "play nothing", so the last checked type stays.
    private func typeBinding(_ type: ClipType) -> Binding<Bool> {
        Binding(get: { model.settings.browse.types.contains(type) },
                set: { value in
                    var browse = model.settings.browse
                    if value {
                        browse.types.insert(type)
                    } else if !browse.types.subtracting([type]).isEmpty {
                        browse.types.remove(type)
                    }
                    model.update(browse: browse)
                })
    }
}
