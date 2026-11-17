import SwiftUI

struct RootView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        @Bindable var store = store
        if store.isConfigured {
            HomeView()
                .sheet(item: $store.presentedDetail) { item in
                    DeviceDetailView(entityId: item.id)
                }
                .sheet(isPresented: $store.isShowingSettings) {
                    SettingsView()
                }
        } else {
            SetupView()
        }
    }
}
