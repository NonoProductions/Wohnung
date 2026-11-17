import SwiftUI

struct SettingsView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isEditingConnection = false
    @State private var isConfirmingSignOut = false
    @State private var isSortingFavorites = false
    @State private var isSortingRooms = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Räume sortieren") { isSortingRooms = true }
                        .disabled(store.rooms.count < 2)
                } footer: {
                    Text("Lege fest, in welcher Reihenfolge die Räume in der Übersicht erscheinen.")
                }

                HeatingSettingsSection(settings: store.heatingSettings)

                Section("Verbindung") {
                    LabeledContent("Status") {
                        Label(statusText, systemImage: statusSymbol)
                            .foregroundStyle(statusColor)
                    }
                    if let local = store.configuration?.localURL {
                        LabeledContent("Im WLAN", value: local.absoluteString)
                    }
                    if let external = store.configuration?.externalURL {
                        LabeledContent("Unterwegs", value: external.absoluteString)
                    }
                    Button("Verbindung bearbeiten") { isEditingConnection = true }
                    Button("Neu verbinden") { store.restart() }
                }

                Section {
                    Button("Widget-Favoriten sortieren") { isSortingFavorites = true }
                        .disabled(store.favorites.isEmpty)
                } footer: {
                    Text("Halte eine Kachel gedrückt und tippe auf den Stern. Die ersten vier Favoriten erscheinen im Widget.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("„Schalte Stehlampe 1 mit Zuhause ein“")
                        Text("„Schalte Flur 1 mit Zuhause aus“")
                    }
                    .font(.callout)
                } header: {
                    Text("Siri")
                } footer: {
                    Text("Apple verlangt den App-Namen im Satz. Für kürzere Befehle wie „Stehlampe an“ lege in der Kurzbefehle-App einen eigenen Kurzbefehl mit der Aktion „Gerät einschalten“ an.")
                }

                Section {
                    Button("Abmelden", role: .destructive) { isConfirmingSignOut = true }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fertig") { dismiss() }
            }
            .sheet(isPresented: $isEditingConnection) {
                SetupView(isEditing: true)
            }
            .sheet(isPresented: $isSortingRooms) {
                RoomOrderView()
            }
            .sheet(isPresented: $isSortingFavorites) {
                FavoritesOrderView()
            }
            .confirmationDialog("Abmelden?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Abmelden und Token löschen", role: .destructive) { store.signOut() }
            } message: {
                Text("Der Token wird aus dem Schlüsselbund entfernt.")
            }
        }
    }

    private var statusText: String {
        switch store.status {
        case .connected: "Verbunden"
        case .connecting: "Verbinde …"
        case .waiting: "Offline"
        case .failed: "Fehler"
        case .idle: "Getrennt"
        }
    }

    private var statusSymbol: String {
        switch store.status {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .waiting: "wifi.slash"
        case .failed: "xmark.octagon.fill"
        case .idle: "pause.circle"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .connected: .green
        case .failed: .red
        case .waiting: .orange
        default: .secondary
        }
    }
}

/// Fixed temperatures per mode and the morning warm-up.
private struct HeatingSettingsSection: View {
    @Environment(HomeStore.self) private var store
    let settings: HeatingSettings

    var body: some View {
        if !settings.entityIds.isEmpty {
            Section {
                ForEach(store.rooms.filter { $0.heating?.warmup != nil }) { room in
                    if let warmup = room.heating?.warmup { temperatureRow("Normal \(room.name)", entity: warmup) }
                }
                if let night = settings.nightTemperature { temperatureRow("Nacht", entity: night) }
                if let away = settings.awayTemperature { temperatureRow("Abwesend", entity: away) }
                if let warmup = settings.morningWarmup {
                    NavigationLink {
                        WakeUpView()
                    } label: {
                        LabeledContent("Morgens aufwärmen", value: warmupSummary(warmup))
                    }
                }
            } header: {
                Text("Heizung")
            } footer: {
                Text("Beim Wechsel des Modus springt der Raum auf diese Temperatur. Am Drehregler kannst du sie jederzeit von Hand ändern, die festen Werte bleiben dabei gleich.")
            }
        }
    }

    private func temperatureRow(_ title: String, entity: HAEntity) -> some View {
        HStack {
            Text(title)
            Spacer()
            ValueStepper(
                value: Double(entity.state),
                step: entity.attributes["step"]?.double ?? 0.5,
                range: (entity.attributes["min"]?.double ?? 7)...(entity.attributes["max"]?.double ?? 30),
                format: { $0.formatted(.number.precision(.fractionLength(1))) + "°" },
                onCommit: { store.setValue(entity, to: $0) }
            )
        }
    }

    private func warmupSummary(_ warmup: HAEntity) -> String {
        guard warmup.state == "on" else { return "Aus" }
        guard let minutes = settings.wakeMinutes else { return "An" }
        return "Warm um \(HeatingSettings.clock(minutes))"
    }
}
