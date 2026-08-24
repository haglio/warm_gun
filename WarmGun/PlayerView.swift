import AVFoundation
import WarmGunKit
import SwiftUI

/// The whole screen: the video, the invisible tap zones over it, and the
/// brief notice a gesture flashes. No HUD — the desktop satellite's map and
/// status band have no place on a phone held in one hand.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingControls = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(player: model.player)
                    .ignoresSafeArea()
                TapLayer(size: geometry.size) { action in
                    if action == .center { showingControls = true } else { model.tap(action) }
                }
                .ignoresSafeArea()
                if model.waitingFor != nil || model.phase == .indexing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                if let notice = model.notice {
                    Text(notice.text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(notice.favorite ? Color.green : Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                        .transition(.opacity)
                        .id(notice.id)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showingControls) {
            ControlsSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// A single tap anywhere fires at once — next and previous must feel like the
/// arrow keys they replace. Only the middle waits for a second tap, because
/// that is where the controls live.
private struct TapLayer: View {
    let size: CGSize
    let onAction: (TapAction) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { tap in
                        if action(at: tap.location) == .center { onAction(.center) }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { tap in
                        let action = action(at: tap.location)
                        if action != .center { onAction(action) }
                    }
            )
    }

    private func action(at point: CGPoint) -> TapAction {
        TapZones.action(x: point.x, y: point.y, width: size.width, height: size.height)
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
