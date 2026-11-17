import SwiftUI

/// Reorder or remove favorites. The first four appear in the widget.
struct FavoritesOrderView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(store.favorites.enumerated()), id: \.element) { index, entityId in
                        let entity = store.entities[entityId]
                        HStack(spacing: 12) {
                            Image(systemName: entity?.symbolName ?? "questionmark.circle")
                                .foregroundStyle(entity?.tint ?? .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(entity.map { store.displayName(for: $0, inRoom: nil) } ?? entityId)
                                if let room = store.areaName(for: entityId) {
                                    Text(room).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if index < 4 {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Im Widget")
                            }
                        }
                    }
                    .onMove { store.moveFavorites(from: $0, to: $1) }
                    .onDelete { store.removeFavorites(at: $0) }
                } footer: {
                    Text("Die ersten vier Favoriten erscheinen im Widget auf dem Homescreen.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favoriten sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fertig") { dismiss() }
            }
        }
    }
}
