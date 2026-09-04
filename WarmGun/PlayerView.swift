import AVFoundation
import SwiftUI
import WarmGunKit

/// The whole screen: the video, the invisible tap zones over it, and — one
/// center tap away — the control overlay: corner clusters for types, order,
/// loop and settings, edge buttons for the four gestures, pause in the middle.
/// There is no menu screen; everything is laid over the picture.
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
            }
            .onChange(of: geometry.size) { _, size in
                model.deviceRotated(landscape: size.width > size.height)
            }
            .onAppear {
                model.deviceRotated(landscape: geometry.size.width > geometry.size.height)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .animation(.easeOut(duration: 0.15), value: showingControls)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
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
            // Corners. Portrait stacks a cluster vertically; landscape lays it
            // flat, where height is the scarce direction.
            corner(.topLeading) {
                cluster {
                    chip("Genau", on: typeBinding(.genau))
                    chip("Shorts", on: typeBinding(.short))
                    // The acts lane's name is library vocabulary: it exists
                    // only when the bundled overlay defines it.
                    if let label = model.overlay.actsLabel {
                        chip(label, on: typeBinding(.acts))
                    }
                    chip("Full", on: typeBinding(.fullLength))
                }
            }
            corner(.topTrailing) {
                cluster {
                    chip("Shuffle", on: orderBinding(latest: false))
                    chip("Latest", on: orderBinding(latest: true))
                    chip("Favs", on: favoritesBinding())
                }
            }
            corner(.bottomLeading) {
                cluster {
                    loopChip("All", .all)
                    loopChip("1", .single)
                    loopChip("Seed", .seed, enabled: model.seedLoopAvailable)
                    loopChip("Action", .action, enabled: model.actionLoopAvailable)
                }
            }
            // The combinable act buttons, overlay-defined: 2 wide and 4 tall in
            // portrait, 4 wide and 2 tall in landscape. Settings has no door
            // here — the login screen appears by itself when a login is needed.
            corner(.bottomTrailing) {
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
            edge(.leading) { iconButton("backward.frame.fill") { act(.previous) } }
            edge(.trailing) { iconButton("forward.frame.fill") { act(.next) } }
            edge(.top) { iconButton("hand.thumbsdown.fill") { act(.weird) } }
            edge(.bottom) {
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
    /// a four-chip row cannot reach the edge buttons at top and bottom center.
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

    private func corner(_ alignment: Alignment, @ViewBuilder _ content: () -> some View) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func edge(_ side: Alignment, @ViewBuilder _ content: () -> some View) -> some View {
        let alignment: Alignment = switch side {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        default: .bottom
        }
        return content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func actChip(_ label: String) -> some View {
        let enabled = !model.settings.browse.disabledActs.contains(label)
        return Button {
            onAnyInteraction()
            var browse = model.settings.browse
            if enabled {
                browse.disabledActs.insert(label)
            } else {
                browse.disabledActs.remove(label)
            }
            model.update(browse: browse)
        } label: {
            Text(label)
                .frame(minWidth: 40, minHeight: 34)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(enabled ? .bold : .regular))
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .background(enabled ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.45), in: Capsule())
        .foregroundStyle(enabled ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.45)))
        .contentShape(Capsule())
    }

    private func chip(_ label: String, on binding: Binding<Bool>) -> some View {
        Button {
            onAnyInteraction()
            binding.wrappedValue.toggle()
        } label: {
            Text(label)
                .frame(minWidth: 84, minHeight: 34)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(binding.wrappedValue ? .bold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(binding.wrappedValue ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.45), in: Capsule())
        .foregroundStyle(.white)
        .contentShape(Capsule())
    }

    private func loopChip(_ label: String, _ mode: AppModel.LoopMode, enabled: Bool = true) -> some View {
        let selected = model.loopMode == mode
        return Button {
            onAnyInteraction()
            model.setLoop(mode)
        } label: {
            Text(label)
                .frame(minWidth: 84, minHeight: 34)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(selected ? .bold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.45), in: Capsule())
        .foregroundStyle(enabled ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.3)))
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

    /// Membership of one type in the browse. Unchecking everything is allowed
    /// — the screen just says nothing matches until a type comes back.
    private func typeBinding(_ type: ClipType) -> Binding<Bool> {
        Binding(get: { model.settings.browse.types.contains(type) },
                set: { value in
                    var browse = model.settings.browse
                    if value {
                        browse.types.insert(type)
                    } else {
                        browse.types.remove(type)
                    }
                    model.update(browse: browse)
                })
    }

    /// The desktop's F-mode. It was taken off the sheet while the phone had
    /// only its own favorites to show; Evolver now flags every one of the
    /// desktop's on the sidecars, so the switch has a library behind it again.
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

/// AVPlayerLayer in a UIView, aspect-fit so a landscape clip on a portrait
/// phone (or the reverse) letterboxes rather than crops.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    /// Fires with the layer's own is-a-frame-on-the-glass fact — the only
    /// signal that does not lie during a big file's black opening seconds.
    let onReadyForDisplay: (Bool) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.observeReadiness(onReadyForDisplay)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var readiness: NSKeyValueObservation?

        func observeReadiness(_ onChange: @escaping (Bool) -> Void) {
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { onChange(ready) }
            }
        }
    }
}
