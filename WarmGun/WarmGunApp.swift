import SwiftUI

@main
struct WarmGunApp: App {
    @StateObject private var model = AppModel()
    @State private var displayLock = DisplayLock()

    var body: some Scene {
        Platform.window {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task { await model.launch() }
                // The screen stays lit only while the app is on it; the
                // picture pauses and the journal leaves for the cloud whenever
                // the app steps aside.
                .onReceive(NotificationCenter.default.publisher(for: Platform.cameToFront)) { _ in
                    displayLock.hold(true)
                    model.becameActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: Platform.steppedAside)) { _ in
                    displayLock.hold(false)
                    model.steppedAside()
                }
                .onReceive(NotificationCenter.default.publisher(for: Platform.willTerminate)) { _ in
                    model.flushState()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.phase {
        case .ready, .indexing:
            PlayerView()
        case .needsLogin, .needsLibrary, .failed:
            SetupView()
        }
    }
}
