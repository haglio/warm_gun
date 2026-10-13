import AVFoundation
import SwiftUI
import WarmGunKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Where the phone and the Mac part ways, and nowhere else. The gate in
/// `tools/gates.py` holds every `#if os(...)` and every UIKit or AppKit import
/// to this file, so the rest of the app is one program that asks these
/// questions in one vocabulary and never knows which machine answers.
enum Platform {
    /// The phone's screen turns with the phone and the browse follows it. A
    /// laptop's does not, so there the orientation is a chip on the overlay.
    #if os(iOS)
    static let screenTurns = true
    #else
    static let screenTurns = false
    #endif

    /// Reports each turn of the device as "landscape?". The view's geometry
    /// hook also reports this, but the device notification arrives even when
    /// a layout pass does not, so both roads lead to the model. A Mac has no
    /// such notification and never calls back.
    static func observeRotation(_ onTurn: @escaping @MainActor (Bool) -> Void) {
        #if os(iOS)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in
                switch UIDevice.current.orientation {
                case .portrait, .portraitUpsideDown: onTurn(false)
                case .landscapeLeft, .landscapeRight: onTurn(true)
                default: break  // face up/down says nothing about the screen
                }
            }
        }
        #endif
    }

    /// Ambient, mixed: this player is muted video — it must never barge in
    /// on whatever the phone is already playing (the default solo-ambient
    /// session pauses other audio the moment playback starts). A Mac has no
    /// audio session to claim.
    static func configureSilentPlayback() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif
    }

    /// Holds the process alive through work that outlives the foreground —
    /// without an assertion iOS suspends the app mid-upload and the journal
    /// never leaves. Returns the release. A Mac never suspends the app.
    static func holdForBackgroundWork() -> () -> Void {
        #if os(iOS)
        let assertion = UIApplication.shared.beginBackgroundTask()
        return { if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) } }
        #else
        return {}
        #endif
    }

    /// Which library a fresh install opens on: the phone is held upright,
    /// the laptop's screen is wide.
    #if os(iOS)
    static let defaultOrientation = Orientation.portrait
    #else
    static let defaultOrientation = Orientation.landscape
    #endif

    /// Posted as the process is about to end — the last chance to write.
    #if os(iOS)
    static let willTerminate = UIApplication.willTerminateNotification
    #else
    static let willTerminate = NSApplication.willTerminateNotification
    #endif

    /// The file each machine uploads. The phone and the Mac share one sync
    /// folder and Evolver reads every `.jsonl` in it, so each needs a name
    /// of its own or the two would overwrite each other's.
    #if os(iOS)
    static let journalFileName = "warm-gun-journal.jsonl"
    #else
    static let journalFileName = "warm-gun-journal-mac.jsonl"
    #endif

    /// The Keychain stand-in for development: the Simulator and a Mac debug
    /// build run against `tools/fake_pcloud.py`, which accepts any token, and
    /// letting the launch environment supply it is what makes the whole app
    /// drivable headlessly with no credentials. Device builds and a Mac
    /// Release build compile this out.
    static var developmentToken: String? { developmentOverride("WARMGUN_TOKEN") }

    /// The API origin for the same runs — `http://localhost:8765` for the
    /// stand-in server — since the login form no longer has a host field.
    static var developmentAPIHost: String? { developmentOverride("WARMGUN_API_HOST") }

    private static func developmentOverride(_ name: String) -> String? {
        #if targetEnvironment(simulator) || (os(macOS) && DEBUG)
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }
}

/// Whether the picture is on screen and in front — the one fact that decides
/// whether the run plays, the display stays lit, and the journal leaves.
///
/// On the phone that is "not in the background": iOS suspends a backgrounded
/// app anyway, and a passing banner must not stop the run. A Mac app is never
/// suspended, so there it is the app being active AND a window being visible:
/// minimized, closed, covered or on another Space, the run would otherwise
/// play on and book completions nobody watched.
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

/// Keeps the display lit while the picture is on it.
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
    /// The app's one window. On the Mac it is exactly one — no New Window,
    /// no second run on the one model — with no title bar over the picture.
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
    /// Nothing of the system over the picture: no status bar and no home
    /// indicator on the phone; on the Mac the window takes the whole screen
    /// the moment the player appears.
    func claimingTheWholeScreen() -> some View {
        #if os(iOS)
        statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        #else
        modifier(WholeScreenClaim())
        #endif
    }

    /// An email address is being typed: the phone offers the keyboard for
    /// one and keeps its hands off the capitalization.
    func emailEntry() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// The small title in the bar, where the phone has a large one to decline.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Takes the window full screen once: the first time it is the key window
/// after the player appears. Once, because leaving full screen by hand must
/// stick, and the window becomes key again on the way out.
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
        // The window may be mid-setup on the appearance that found it key.
        DispatchQueue.main.async {
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }
}
#endif

/// AVPlayerLayer in a system view, aspect-fit so a landscape clip on a
/// portrait phone (or the reverse, or either on a laptop) letterboxes rather
/// than crops. `onReadyForDisplay` fires with the layer's own
/// is-a-frame-on-the-glass fact — the only signal that does not lie during a
/// big file's black opening seconds.
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
