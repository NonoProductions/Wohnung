import SwiftUI

@main
struct ZuhauseApp: App {
    @State private var store = HomeStore()
    @State private var appleScenes = AppleHomeScenes()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(appleScenes)
                #if DEBUG
                .onAppear { DebugLaunchOptions.apply(to: store) }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.scenePhaseChanged(phase)
            if phase == .active {
                appleScenes.onError = { [store] in store.showError($0) }
                appleScenes.start()
            }
        }
    }
}
