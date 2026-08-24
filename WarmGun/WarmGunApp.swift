import SwiftUI

@main
struct WarmGunApp: App {
    @StateObject private var model = AppModel()
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
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                    if phase == .active { model.becameActive() }
                    if phase == .background {
                        model.flushState()
                        Task { await model.syncWithCloud() }
                    }
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
