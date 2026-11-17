import SwiftUI

#if DEBUG

/// Debug-only hooks for testing in the simulator against a mock server, driven by environment variables:
/// `ZUHAUSE_DEBUG_URL`, `ZUHAUSE_DEBUG_TOKEN`, `ZUHAUSE_DEBUG_FAVORITES` (comma separated)
/// `ZUHAUSE_DEBUG_TAPS` (comma separated entity ids tapped a few seconds after launch),
/// `ZUHAUSE_DEBUG_SETTINGS=1` (opens the settings), `ZUHAUSE_DEBUG_ROOM` (area id), `ZUHAUSE_DEBUG_HEATING=1` (opens its heating dial),
/// `ZUHAUSE_DEBUG_WAKEUP=1` (opens the morning warm-up)
/// `ZUHAUSE_DEBUG_DETAIL` (entity id whose detail sheet opens) and `ZUHAUSE_DEBUG_CHART_HOURS_AGO` (selects that time in its chart).
@MainActor
enum DebugLaunchOptions {
    static func apply(to store: HomeStore) {
        let environment = ProcessInfo.processInfo.environment
        if let url = environment["ZUHAUSE_DEBUG_URL"].flatMap(ServerConfiguration.normalize),
           let token = environment["ZUHAUSE_DEBUG_TOKEN"] {
            try? store.configure(ServerConfiguration(localURL: url, externalURL: nil), token: token)
        }
        if let favorites = environment["ZUHAUSE_DEBUG_FAVORITES"] {
            for id in favorites.split(separator: ",").map(String.init) where !store.isFavorite(id) {
                store.toggleFavorite(id)
            }
        }
        if environment["ZUHAUSE_DEBUG_SETTINGS"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(3))
                store.isShowingSettings = true
            }
        }
        if let room = environment["ZUHAUSE_DEBUG_ROOM"] {
            store.roomPath = [room]
        }
        if let detail = environment["ZUHAUSE_DEBUG_DETAIL"] {
            Task {
                try? await Task.sleep(for: .seconds(3))
                store.showDetail(detail)
            }
        }
        if let taps = environment["ZUHAUSE_DEBUG_TAPS"] {
            Task {
                try? await Task.sleep(for: .seconds(4))
                for id in taps.split(separator: ",").map(String.init) {
                    if let entity = store.entities[id] { store.tap(entity) }
                }
            }
        }
    }
}
#endif

extension View {
    /// Debug: `ZUHAUSE_DEBUG_SCROLL=bottom` starts scroll views at the end (for screenshots).
    func debugScrollAnchor() -> some View {
        #if DEBUG
        defaultScrollAnchor(ProcessInfo.processInfo.environment["ZUHAUSE_DEBUG_SCROLL"] == "bottom" ? .bottom : .top)
        #else
        self
        #endif
    }
}
