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
                    HStack(spacing: 8) {
                        loopButton("All", .all)
                        loopButton("1", .single)
                        // Greyed when the clip on screen has no group to loop —
                        // a press that could only dead-end is not offered.
                        loopButton("Seed", .seed, enabled: model.seedLoopAvailable)
                        loopButton("Action", .action, enabled: model.actionLoopAvailable)
                    }
                    if model.seedLoopAvailable == false && model.actionLoopAvailable == false,
                       let problem = model.metadataProblem {
                        Text("Metadata index unavailable: \(problem)")
                            .font(.footnote)
                            .foregroundStyle(.red)
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

    private func loopButton(_ label: String, _ mode: AppModel.LoopMode, enabled: Bool = true) -> some View {
        let selected = model.loopMode == mode
        return Button(label) { model.setLoop(mode) }
            .buttonStyle(.plain)
            .font(.subheadline.weight(selected ? .bold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(enabled ? .primary : .tertiary)
            .disabled(!enabled)
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
