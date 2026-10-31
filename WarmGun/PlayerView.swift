import SwiftUI
import WarmGunKit

/// The whole screen: the video, the invisible tap zones over it, and — one
/// center tap away — the control overlay: corner clusters for types, order,
/// loop and the act buttons, edge buttons for the four gestures, pause in the
/// middle. There is no menu screen; everything is laid over the picture.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(player: model.player) { ready in
                    model.setLayerReady(ready)
                }
                .ignoresSafeArea()
                TapLayer { action in
                    model.tap(action)
                    if showingControls { keepControlsAlive() }
                } onCenterTap: {
                    showingControls ? hideControls() : revealControls()
                } onCenterDoubleTap: {
                    model.togglePause()
                }
                .ignoresSafeArea()
                if model.phase == .ready && model.catalog != nil && model.session.playlist.isEmpty {
                    Text("Nothing matches these filters")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                } else if model.phase == .indexing
                            || (model.showing == nil && model.waitingFor != nil)
                            || model.buffering
                            || (model.showing != nil && !model.layerReady) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text(model.phase == .indexing ? "Indexing the library…" : "Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                VStack {
                    if let notice = model.notice {
                        Text(notice.text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(notice.favorite ? Color.green : Color.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .transition(.opacity)
                            .id(notice.id)
                    }
                    HStack(spacing: 8) {
                        if model.waitingFor != nil && model.showing != nil {
                            pill { ProgressView().controlSize(.mini).tint(.white); Text("fetching") }
                        }
                        if model.session.locked {
                            pill { Image(systemName: "lock.fill"); Text("locked") }
                        }
                        if model.paused && !showingControls {
                            pill { Image(systemName: "pause.fill"); Text("paused") }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 24)
                if showingControls {
                    ControlsOverlay(landscape: landscape,
                                    onAnyInteraction: keepControlsAlive)
                        .transition(.opacity)
                }
                KeyboardShortcuts()
            }
            .onChange(of: geometry.size) { _, size in
                model.deviceRotated(landscape: size.width > size.height)
            }
            // A pointer, where there is one: moving it wakes the controls and
            // keeps them awake, the way a touch does. A finger never hovers.
            .onContinuousHover { phase in
                guard case .active = phase else { return }
                showingControls ? keepControlsAlive() : revealControls()
            }
            .onAppear {
                model.deviceRotated(landscape: geometry.size.width > geometry.size.height)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .animation(.easeOut(duration: 0.15), value: showingControls)
        .claimingTheWholeScreen()
    }

    private func revealControls() {
        showingControls = true
        keepControlsAlive()
    }

    private func hideControls() {
        hideTask?.cancel()
        showingControls = false
    }

    /// The overlay outlives its last touch by a few seconds, then gets out of
    /// the picture's way.
    private func keepControlsAlive() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            showingControls = false
        }
    }

    @ViewBuilder
    private func pill(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 5) { content() }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45), in: Capsule())
    }
}

/// The four corners and four edges, over the playing picture.
private struct ControlsOverlay: View {
    @EnvironmentObject private var model: AppModel
    let landscape: Bool
    let onAnyInteraction: () -> Void

    var body: some View {
        ZStack {
            pinned(.topLeading) {
                cluster {
                    chip("Genau", on: typesBinding([.genauFlick]))
                    chip("Clips", on: typesBinding(ClipType.clips))
                    chip("Full", on: typesBinding([.fullLength]))
                }
            }
            pinned(.topTrailing) {
                cluster {
                    chip("Shuffle", on: orderBinding(latest: false))
                    chip("Latest", on: orderBinding(latest: true))
                    chip("Favs", on: favoritesBinding())
                }
            }
            // The Loop control, laid so that E's cycle (all, 1, seed, action)
            // runs clockwise round the landscape grid: All and 1 on top,
            // Seed under 1 and Action under All.
            pinned(.bottomLeading) {
                cluster {
                    loopChip("All", .all)
                    loopChip("1", .single)
                    loopChip("Action", .action, enabled: model.canLoop(.action))
                    loopChip("Seed", .seed, enabled: model.canLoop(.seed))
                }
            }
            // The combinable act buttons, overlay-defined: 2 wide and 4 tall in
            // portrait, 4 wide and 2 tall in landscape. Settings has no door
            // here — the login screen appears by itself when a login is needed.
            pinned(.bottomTrailing) {
                if !model.overlay.actFilters.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                             count: landscape ? 4 : 2),
                              alignment: .trailing, spacing: 5) {
                        ForEach(model.overlay.actFilters, id: \.label) { filter in
                            actChip(filter.label)
                        }
                    }
                    .frame(width: landscape ? 200 : 104)
                }
            }
            // Edges: the four gestures, drawn where their tap zones live.
            pinned(.leading) { iconButton("backward.frame.fill") { act(.previous) } }
            pinned(.trailing) { iconButton("forward.frame.fill") { act(.next) } }
            pinned(.top) { iconButton("hand.thumbsdown.fill") { act(.weird) } }
            lowEdge {
                iconButton(model.session.locked ? "lock.fill" : "lock.open") { act(.lock) }
            }
            // Dead center: pause, the one control with no zone of its own.
            iconButton(model.paused ? "play.fill" : "pause.fill", large: true) {
                onAnyInteraction()
                model.togglePause()
            }
            // The name of what is on the glass, under the pause button: the
            // only band clear of the corner clusters and the edge buttons,
            // which sit at the centers of the sides.
            if let name = model.showing.flatMap(LibraryPaths.filename(ofClip:)) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: landscape ? 360 : 230)
                    .offset(y: landscape ? 62 : 74)
            }
        }
        .padding(18)
    }

    private func act(_ action: TapAction) {
        onAnyInteraction()
        model.tap(action)
    }

    /// Portrait stacks a cluster tall; landscape folds it into a 2x2 grid so
    /// a four-chip row cannot reach the edge buttons at top and lower center.
    @ViewBuilder
    private func cluster(@ViewBuilder _ content: () -> some View) -> some View {
        if landscape {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                      alignment: .leading, spacing: 6) { content() }
                .frame(width: 220)
        } else {
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }

    private func pinned(_ alignment: Alignment, @ViewBuilder _ content: () -> some View) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// The low edge, stacked rather than aligned.  SwiftUI's name for that
    /// alignment is a word this project no longer writes, and a spacer above
    /// the content leaves it in the same place.
    private func lowEdge(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            Spacer()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actChip(_ label: String) -> some View {
        let shown = !model.settings.browse.disabledActs.contains(label)
        return capsuleButton(label, selected: shown, opacity: shown ? 1 : 0.45, compact: true) {
            var browse = model.settings.browse
            if shown {
                browse.disabledActs.insert(label)
            } else {
                browse.disabledActs.remove(label)
            }
            model.update(browse: browse)
        }
    }

    private func chip(_ label: String, on binding: Binding<Bool>) -> some View {
        capsuleButton(label, selected: binding.wrappedValue) { binding.wrappedValue.toggle() }
    }

    private func loopChip(_ label: String, _ mode: LoopMode, enabled: Bool = true) -> some View {
        capsuleButton(label, selected: model.loopMode == mode, opacity: enabled ? 1 : 0.3, enabled: enabled) {
            model.setLoop(mode)
        }
    }

    private func capsuleButton(_ label: String, selected: Bool, opacity: Double = 1, enabled: Bool = true,
                               compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            onAnyInteraction()
            action()
        } label: {
            Text(label)
                .frame(minWidth: compact ? 40 : 84, minHeight: 34)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(selected ? .bold : .regular))
        .padding(.horizontal, compact ? 2 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(selected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.45), in: Capsule())
        .foregroundStyle(.white.opacity(opacity))
        .disabled(!enabled)
        .contentShape(Capsule())
    }

    private func iconButton(_ systemName: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(large ? .title : .title3)
                .foregroundStyle(.white)
                .padding(large ? 18 : 13)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Whether every kind a chip covers is in the browse. Unchecking everything is allowed
    /// — the screen just says nothing matches until a type comes back.
    private func typesBinding(_ kinds: Set<ClipType>) -> Binding<Bool> {
        Binding(get: { model.settings.browse.includes(kinds) },
                set: { value in
                    var browse = model.settings.browse
                    browse.setIncluded(kinds, value)
                    model.update(browse: browse)
                })
    }

    /// The desktop's F-mode.
    private func favoritesBinding() -> Binding<Bool> {
        Binding(get: { model.settings.browse.favoritesOnly },
                set: { value in
                    var browse = model.settings.browse
                    browse.favoritesOnly = value
                    model.update(browse: browse)
                })
    }

    private func orderBinding(latest: Bool) -> Binding<Bool> {
        Binding(get: { model.settings.browse.latest == latest },
                set: { _ in
                    var browse = model.settings.browse
                    browse.latest = latest
                    model.update(browse: browse)
                })
    }
}

/// The keyboard, where there is one. The arrows are the desktop satellite's
/// — left previous, right next, up weird, down lock — and WASD is the same
/// hand on the same four; E steps the Loop control clockwise, all, 1, seed,
/// action; space and Esc pause and play; P and L pick the portrait or the
/// landscape library, since a laptop's screen never turns.
/// Buttons SwiftUI never draws, so each key equivalent has somewhere to land
/// whatever is on screen; the login form is a different screen and never
/// sees them.
private struct KeyboardShortcuts: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            gesture(.previous, .leftArrow, "a")
            gesture(.next, .rightArrow, "d")
            gesture(.weird, .upArrow, "w")
            gesture(.lock, .downArrow, "s")
            Button("Loop") { model.cycleLoop() }
                .keyboardShortcut("e", modifiers: [])
            Button("Pause") { model.togglePause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Pause") { model.togglePause() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("Portrait") { model.setOrientation(.portrait) }
                .keyboardShortcut("p", modifiers: [])
            Button("Landscape") { model.setOrientation(.landscape) }
                .keyboardShortcut("l", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func gesture(_ action: TapAction, _ arrow: KeyEquivalent, _ letter: KeyEquivalent) -> some View {
        Button(String(describing: action)) { model.tap(action) }
            .keyboardShortcut(arrow, modifiers: [])
        Button(String(describing: action)) { model.tap(action) }
            .keyboardShortcut(letter, modifiers: [])
    }
}

/// A single tap on an edge zone fires at once — next and previous must feel
/// like the arrow keys they replace. The middle summons the controls with one
/// tap and pauses with two.
private struct TapLayer: View {
    let onAction: (TapAction) -> Void
    let onCenterTap: () -> Void
    let onCenterDoubleTap: () -> Void
    @State private var pendingCenter: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { tap in
                            guard action(at: tap.location, in: geometry.size) == .center else { return }
                            pendingCenter?.cancel()
                            pendingCenter = nil
                            onCenterDoubleTap()
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { tap in
                            let action = action(at: tap.location, in: geometry.size)
                            if action == .center {
                                pendingCenter?.cancel()
                                pendingCenter = Task {
                                    try? await Task.sleep(for: .milliseconds(280))
                                    guard !Task.isCancelled else { return }
                                    onCenterTap()
                                }
                            } else {
                                onAction(action)
                            }
                        }
                )
        }
    }

    private func action(at point: CGPoint, in size: CGSize) -> TapAction {
        TapZones.action(x: point.x, y: point.y, width: size.width, height: size.height)
    }
}
