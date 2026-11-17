import SwiftUI

/// Overview: heating shortcuts and one card per room.
struct HomeView: View {
    @Environment(HomeStore.self) private var store
    @Environment(AppleHomeScenes.self) private var appleScenes

    var body: some View {
        @Bindable var store = store
        let rooms = store.rooms
        NavigationStack(path: $store.roomPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HeatingQuickActions()
                    WakeUpCard()

                    // Apple Home scenes spanning several rooms (or rooms the app does not have).
                    let otherScenes = appleScenes.otherScenes(roomNames: rooms.map(\.name))
                    if !rooms.isEmpty, !otherScenes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Szenen", symbol: "sparkles")
                            SceneGrid(scenes: otherScenes)
                        }
                    }

                    if !rooms.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Räume", symbol: "square.split.2x2.fill")
                            TileGrid(spacing: 12) {
                                ForEach(rooms) { room in
                                    RoomCard(room: room) { store.roomPath.append(room.id) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                // Without rooms the stack is empty; keep the scroll view (and its overlays) full width.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zuhause")
            .toolbar {
                Button("Einstellungen", systemImage: "gearshape") { store.isShowingSettings = true }
            }
            .navigationDestination(for: String.self) { roomId in
                RoomView(roomId: roomId)
            }
            .overlay {
                if rooms.isEmpty { LoadingState().transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.3), value: rooms.isEmpty)
            .overlay(alignment: .top) { StatusBanner() }
            .refreshable { store.restart() }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// Room card on the overview: climate at a glance plus a light switch for the whole room.
private struct RoomCard: View {
    @Environment(HomeStore.self) private var store
    let room: Room
    let onOpen: () -> Void

    var body: some View {
        let lightsOn = room.lightsOn
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: room.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(lightsOn.isEmpty ? Color.secondary : Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(lightsOn.isEmpty ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.yellow.gradient)))
                Spacer()
                if !room.lights.isEmpty {
                    Button {
                        store.setLights(lightsOn.isEmpty ? room.lights : lightsOn, on: lightsOn.isEmpty)
                    } label: {
                        Image(systemName: lightsOn.isEmpty ? "lightbulb" : "lightbulb.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(lightsOn.isEmpty ? Color.secondary : Color.yellow)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lightsOn.isEmpty ? "Licht im \(room.name) an" : "Licht im \(room.name) aus")
                }
            }

            Text(room.name)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 10) {
                if let temperature = room.currentTemperature {
                    Label(HAEntity.formatTemperature(temperature), systemImage: room.isHeating ? "flame.fill" : "thermometer.medium")
                        .foregroundStyle(room.isHeating ? Color.orange : Color.secondary)
                }
                if let humidity = room.humidity.flatMap({ Double($0.state) }) {
                    Label("\(Int(humidity.rounded())) %", systemImage: "humidity")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            .monospacedDigit()

            Text(statusLine(lightsOn: lightsOn.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.yellow.opacity(lightsOn.isEmpty ? 0 : 0.1)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
        .animation(.snappy, value: lightsOn.count)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Öffnen", onOpen)
    }

    private func statusLine(lightsOn: Int) -> String {
        var parts: [String] = []
        if !room.lights.isEmpty {
            parts.append(lightsOn == 0 ? "Licht aus" : lightsOn == 1 ? "1 Licht an" : "\(lightsOn) Lichter an")
        }
        if let mode = room.heating?.mode?.state { parts.append(mode) }
        return parts.joined(separator: " · ")
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// One room, structured like the room views of the dashboard.
struct RoomView: View {
    @Environment(HomeStore.self) private var store
    @Environment(AppleHomeScenes.self) private var appleScenes
    let roomId: String

    @State private var isShowingHeating = false

    var body: some View {
        let room = store.rooms.first { $0.id == roomId }
        ScrollView {
            if let room {
                VStack(spacing: 16) {
                    RoomClimateHeader(room: room)

                    if let heating = room.heating {
                        HeatingTile(room: room, heating: heating) { isShowingHeating = true }
                    }
                    if let fan = room.fan { HeaterFanCard(fan: fan) }
                    if !room.lights.isEmpty { lightSection(room) }
                    if !room.airSensors.isEmpty {
                        SectionCard("Raumklima", symbol: "aqi.medium", tint: .teal) {
                            TileGrid(spacing: 10) {
                                ForEach(room.airSensors) { sensor in
                                    SensorTile(entity: sensor, name: store.displayName(for: sensor, inRoom: room.name))
                                }
                            }
                        }
                    }
                    if !room.devices.isEmpty {
                        SectionCard("Geräte", symbol: "switch.2", tint: .green) {
                            TileGrid(spacing: 10) {
                                ForEach(room.devices) { device in
                                    DeviceTile(
                                        entity: device,
                                        name: store.displayName(for: device, inRoom: room.name),
                                        isFavorite: store.isFavorite(device.entityId),
                                        onTap: { store.tap(device) },
                                        onLongPress: { store.showDetail(device.entityId) }
                                    )
                                }
                            }
                        }
                    }
                    let scenes = appleScenes.scenes(inRoom: room.name)
                    if !scenes.isEmpty {
                        SectionCard("Szenen", symbol: "sparkles", tint: .purple) { SceneGrid(scenes: scenes) }
                    }
                    if !room.batteries.isEmpty { batterySection(room) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            } else {
                ContentUnavailableView("Raum nicht gefunden", systemImage: "questionmark.square.dashed")
            }
        }
        .debugScrollAnchor()
        .background(Color(.systemGroupedBackground))
        .navigationTitle(room?.name ?? "")
        .overlay(alignment: .top) { StatusBanner() }
        .sheet(isPresented: $isShowingHeating) { HeatingSheet(roomId: roomId) }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["ZUHAUSE_DEBUG_HEATING"] == "1" else { return }
            try? await Task.sleep(for: .seconds(2))
            isShowingHeating = true
        }
        #endif
    }

    private func lightSection(_ room: Room) -> some View {
        let anyOn = !room.lightsOn.isEmpty
        return SectionCard("Licht", symbol: "lightbulb.fill", tint: .yellow) {
            PillButton(title: anyOn ? "Alle aus" : "Alle an", symbol: anyOn ? "lightbulb.slash" : "lightbulb", tint: anyOn ? .secondary : .orange) {
                store.setLights(anyOn ? room.lightsOn : room.lights, on: !anyOn)
            }
        } content: {
            TileGrid(spacing: 10) {
                ForEach(room.lights) { light in
                    LightTile(entity: light, name: store.displayName(for: light, inRoom: room.name))
                }
            }
        }
    }

    private func batterySection(_ room: Room) -> some View {
        SectionCard("Batterien", symbol: "battery.75percent", tint: .gray) {
            VStack(spacing: 0) {
                ForEach(room.batteries) { battery in
                    let level = Double(battery.state)
                    HStack {
                        Text(Self.batteryName(store.displayName(for: battery, inRoom: room.name)))
                            .font(.subheadline)
                        Spacer()
                        Label(battery.sensorValueText, systemImage: Self.batterySymbol(level))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(level.map { $0 < 20 ? Color.red : Color.secondary } ?? Color.secondary)
                    }
                    .padding(.vertical, 8)
                    if battery.entityId != room.batteries.last?.entityId { Divider() }
                }
            }
        }
    }

    /// "Heizung Batterie" → "Heizung"; a bare "Batterie" stays.
    private static func batteryName(_ name: String) -> String {
        let trimmed = name.replacingOccurrences(of: " Batterie", with: "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    private static func batterySymbol(_ level: Double?) -> String {
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Drag rooms into the order shown on the overview.
struct RoomOrderView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.rooms) { room in
                    Label(room.name, systemImage: room.symbol)
                }
                .onMove { store.moveRooms(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Räume sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

private struct LoadingState: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        switch store.status {
        case .failed(let message):
            ContentUnavailableView("Keine Verbindung", systemImage: "wifi.exclamationmark", description: Text(message))
        case .waiting:
            ContentUnavailableView {
                Label("Home Assistant nicht erreichbar", systemImage: "wifi.slash")
            } description: {
                Text("Die App versucht es automatisch weiter.")
            } actions: {
                Button("Jetzt erneut versuchen") { store.restart() }
                    .buttonStyle(.bordered)
            }
        default:
            HomeSkeleton()
        }
    }
}

/// Placeholder in the shape of the overview while the first connection is set up.
private struct HomeSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConnectingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: 18).frame(height: 64)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 80, height: 18)
                        .padding(.leading, 4)
                    TileGrid(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in RoomCardSkeleton() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDisabled(true)
        .background(Color(.systemGroupedBackground))
    }
}

private struct RoomCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonBlock(cornerRadius: 20).frame(width: 40, height: 40)
                Spacer()
                SkeletonBlock(cornerRadius: 20).frame(width: 40, height: 40)
            }
            SkeletonBlock().frame(width: 90, height: 16)
            SkeletonBlock().frame(width: 70, height: 11)
            SkeletonBlock().frame(width: 100, height: 11)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityHidden(true)
    }
}

/// Grey placeholder with a light sweep that runs across the whole screen in sync.
private struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.6
    private static let bandWidth: CGFloat = 180

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        GeometryReader { geo in
                            let frame = geo.frame(in: .global)
                            let progress = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: Self.period) / Self.period
                            // The band travels from off-screen left to off-screen right; lower blocks lag slightly.
                            let center = -Self.bandWidth + progress * 900 - frame.minY * 0.25
                            LinearGradient(
                                colors: [.clear, .white.opacity(colorScheme == .dark ? 0.12 : 0.55), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: Self.bandWidth)
                            .offset(x: center - frame.minX - Self.bandWidth / 2)
                        }
                    }
                    .clipShape(shape)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Small indeterminate progress bar with a caption.
private struct ConnectingIndicator: View {
    private static let period = 1.3

    var body: some View {
        VStack(spacing: 8) {
            Text("Verbinde mit Home Assistant …")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TimelineView(.animation) { context in
                let raw = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period) / Self.period
                let t = raw * raw * (3 - 2 * raw)
                GeometryReader { geo in
                    let segment = geo.size.width * 0.4
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: segment)
                        .offset(x: -segment + t * (geo.size.width + segment))
                }
            }
            .frame(width: 140, height: 4)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verbinde mit Home Assistant")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
