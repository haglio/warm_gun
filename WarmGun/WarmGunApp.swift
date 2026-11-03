import SwiftUI

@main
struct WarmGunApp: App {
    @StateObject private var model = AppModel()
    @State private var presence = Presence()
    @State private var displayLock = DisplayLock()

    var body: some Scene {
        Platform.window {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task { await model.launch() }
                .onAppear {
                    presence.observe { present in
                        displayLock.hold(present)
                        if present { model.becameActive() } else { model.steppedAside() }
                    }
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
