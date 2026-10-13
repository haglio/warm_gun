import SwiftUI

@main
struct WarmGunApp: App {
    @StateObject private var model = AppModel()
    @State private var displayLock = DisplayLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // The screen stays lit only while the app is on it; the
                    // journal leaves for the cloud whenever the app steps aside.
                    displayLock.hold(phase == .active)
                    if phase == .active { model.becameActive() }
                    if Platform.isSteppingAside(phase) {
                        model.flushState()
                        Task { await model.syncWithCloud() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Platform.willTerminate)) { _ in
                    model.flushState()
                }
        }
        .playerWindow()
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
