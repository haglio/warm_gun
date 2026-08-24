import AVFoundation
import WarmGunKit
import SwiftUI

/// The whole screen: the video, the invisible tap zones over it, and the
/// brief notice a gesture flashes. No HUD — just two small state pills (lock,
/// pause) and a fetching indicator, so the truth of the run is visible.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingControls = false
    @State private var showingZones = false
    @State private var zonesTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(player: model.player)
                    .ignoresSafeArea()
                TapLayer { action in
                    if action == .center { showingControls = true } else { model.tap(action) }
                } onPause: {
                    model.togglePause()
                }
                .ignoresSafeArea()
                if showingZones {
                    ZoneOverlay()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                // The big spinner only when there is nothing on the glass at
                // all; over a playing picture a fetch is a small pill, not a
                // shroud.
                if model.showing == nil && (model.waitingFor != nil || model.phase == .indexing) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
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
                        if model.paused {
                            pill { Image(systemName: "pause.fill"); Text("paused") }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 24)
            }
            .onChange(of: geometry.size) { _, size in
                model.deviceRotated(landscape: size.width > size.height)
            }
            .onAppear {
                model.deviceRotated(landscape: geometry.size.width > geometry.size.height)
                flashZones()
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .animation(.easeOut(duration: 0.3), value: showingZones)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showingControls) {
            ControlsSheet()
                .presentationDetents([.medium, .large])
        }
        .onChange(of: showingControls) { _, open in
            if !open { flashZones() }
        }
    }

    /// The zones drawn for a moment — on arrival and whenever the sheet
    /// closes — so the hand can learn where they are without a manual.
    private func flashZones() {
        zonesTask?.cancel()
        showingZones = true
        zonesTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            showingZones = false
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

/// A single tap anywhere fires at once — next and previous must feel like the
/// arrow keys they replace. Only the middle waits a beat, because one tap
/// there is pause and two are the controls, and the pause can afford the
/// double-tap window that tells them apart.
private struct TapLayer: View {
    let onAction: (TapAction) -> Void
    let onPause: () -> Void
    @State private var pendingPause: Task<Void, Never>?

    var body: some View {
        // Measured INSIDE the safe-area-ignoring expansion: the outer
        // geometry is the safe-area frame, which in landscape is pushed off
        // the notch — zones computed from it land visibly left of where the
        // fingers expect them. In here, size and tap share one space.
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { tap in
                            guard action(at: tap.location, in: geometry.size) == .center else { return }
                            pendingPause?.cancel()
                            pendingPause = nil
                            onAction(.center)
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { tap in
                            let action = action(at: tap.location, in: geometry.size)
                            if action == .center {
                                pendingPause?.cancel()
                                pendingPause = Task {
                                    try? await Task.sleep(for: .milliseconds(280))
                                    guard !Task.isCancelled else { return }
                                    onPause()
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

/// The tap map, drawn where the taps land: tinted thirds with their names.
private struct ZoneOverlay: View {
    var body: some View {
        // Its own reader, inside the safe-area expansion, so the map is drawn
        // in exactly the space the taps are measured in.
        GeometryReader { geometry in
            let size = geometry.size
            zones(size: size)
        }
    }

    private func zones(size: CGSize) -> some View {
        let w = size.width / 3
        let h = size.height / 3
        return ZStack {
            zone("PREVIOUS", x: 0, y: 0, width: w, height: size.height, tint: .blue)
            zone("NEXT", x: 2 * w, y: 0, width: w, height: size.height, tint: .blue)
            zone("WEIRD", x: w, y: 0, width: w, height: h, tint: .red)
            zone("PAUSE ·· CONTROLS", x: w, y: h, width: w, height: h, tint: .gray)
            zone("LOCK ★", x: w, y: 2 * h, width: w, height: h, tint: .green)
        }
    }

    private func zone(_ label: String, x: CGFloat, y: CGFloat,
                      width: CGFloat, height: CGFloat, tint: Color) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: width, height: height)
            .background(tint.opacity(0.18))
            .overlay(Rectangle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .position(x: x + width / 2, y: y + height / 2)
    }
}

/// AVPlayerLayer in a UIView, aspect-fit so a landscape clip on a portrait
/// phone (or the reverse) letterboxes rather than crops.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
