import AVFoundation
import SwiftUI
import WarmGunKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Platform {
    #if os(iOS)
    static let screenTurns = true
    #else
    static let screenTurns = false
    #endif

    /// UIDevice's notification arrives even when a layout pass does not.
    static func observeRotation(_ onTurn: @escaping @MainActor (Bool) -> Void) {
        #if os(iOS)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in
                switch UIDevice.current.orientation {
                case .portrait, .portraitUpsideDown: onTurn(false)
                case .landscapeLeft, .landscapeRight: onTurn(true)
                default: break
                }
            }
        }
        #endif
    }

    /// AVAudioSession's default solo-ambient category pauses other audio the moment playback starts.
    static func configureSilentPlayback() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif
    }

    /// Without an assertion iOS suspends the app mid-upload.
    static func holdForBackgroundWork() -> () -> Void {
        #if os(iOS)
        let assertion = UIApplication.shared.beginBackgroundTask()
        return { if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) } }
        #else
        return {}
        #endif
    }

    #if os(iOS)
    static let defaultShape = VideoShape.portrait
    #else
    static let defaultShape = VideoShape.landscape
    #endif

    #if os(iOS)
    static let willTerminate = UIApplication.willTerminateNotification
    #else
    static let willTerminate = NSApplication.willTerminateNotification
    #endif

    #if os(iOS)
    static let journalFileName = "warm-gun-journal.jsonl"
    #else
    static let journalFileName = "warm-gun-journal-mac.jsonl"
    #endif

    static var developmentToken: String? { developmentOverride("WARMGUN_TOKEN") }

    static var developmentAPIHost: String? { developmentOverride("WARMGUN_API_HOST") }

    private static func developmentOverride(_ name: String) -> String? {
        #if targetEnvironment(simulator) || (os(macOS) && DEBUG)
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }
}

/// iOS suspends a backgrounded app anyway, and a passing banner must not stop the run; a macOS app
/// is never suspended, so there this takes the app active and a window visible.
@MainActor
final class Presence {
    private var observers: [NSObjectProtocol] = []
    private var present = false

    func observe(_ onChange: @escaping @MainActor (Bool) -> Void) {
        #if os(iOS)
        let names = [UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification]
        #else
        let names = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification]
        #endif
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let now = Self.isPresent()
                    guard now != self.present else { return }
                    self.present = now
                    onChange(now)
                }
            }
        }
    }

    private static func isPresent() -> Bool {
        #if os(iOS)
        return UIApplication.shared.applicationState != .background
        #else
        return NSApp.isActive && NSApp.windows.contains { $0.occlusionState.contains(.visible) }
        #endif
    }
}

@MainActor
final class DisplayLock {
    #if os(macOS)
    private var activity: NSObjectProtocol?
    #endif

    func hold(_ held: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = held
        #else
        if held, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                             reason: "Warm Gun is playing")
        } else if !held, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        #endif
    }
}

extension Platform {
    static func window<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some Scene {
        #if os(macOS)
        Window("Warm Gun", id: "player") { content() }
            .windowStyle(.hiddenTitleBar)
        #else
        WindowGroup { content() }
        #endif
    }
}

extension View {
    func claimingTheWholeScreen() -> some View {
        #if os(iOS)
        statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        #else
        modifier(WholeScreenClaim())
        #endif
    }

    func emailEntry() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// macOS makes the window key again on the way out of full screen, so the claim happens once.
private struct WholeScreenClaim: ViewModifier {
    @State private var claimed = false

    func body(content: Content) -> some View {
        content
            .onAppear { claim(NSApp.keyWindow) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                claim(note.object as? NSWindow)
            }
    }

    private func claim(_ window: NSWindow?) {
        guard !claimed, let window else { return }
        claimed = true
        // AppKit may still be setting up the window on the appearance that found it key.
        DispatchQueue.main.async {
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }
}
#endif

/// AVPlayerLayer's isReadyForDisplay is the only signal that does not lie during a big file's
/// black opening seconds.
#if os(iOS)
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
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
#else
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: (Bool) -> Void

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.observeReadiness(onReadyForDisplay)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        if nsView.playerLayer.player !== player { nsView.playerLayer.player = player }
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        private var readiness: NSKeyValueObservation?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            playerLayer.backgroundColor = NSColor.black.cgColor
            layer = playerLayer
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func observeReadiness(_ onChange: @escaping (Bool) -> Void) {
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { onChange(ready) }
            }
        }
    }
}
#endif
