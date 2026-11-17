import Charts
import SwiftUI

struct DeviceDetailView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entityId: String

    var body: some View {
        NavigationStack {
            Group {
                if let entity = store.entities[entityId] {
                    ScrollView {
                        VStack(spacing: 28) {
                            DetailHeader(entity: entity, room: store.areaName(for: entityId))
                            controls(for: entity)
                                .disabled(entity.isUnavailable)
                                .opacity(entity.isUnavailable ? 0.4 : 1)
                        }
                        .padding(20)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation(.snappy) { store.toggleFavorite(entityId) }
                            } label: {
                                Image(systemName: store.isFavorite(entityId) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                            }
                            .accessibilityLabel(store.isFavorite(entityId) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                        }
                    }
                } else {
                    ContentUnavailableView("Gerät nicht gefunden", systemImage: "questionmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        // A solid sheet background; on the default glass the scroll content showed as a lighter column while opening.
        .presentationBackground(Color(.systemGroupedBackground))
        // Sensors open high enough to show their chart.
        .presentationDetents(store.entities[entityId]?.kind == .sensor ? [.fraction(0.75), .large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func controls(for entity: HAEntity) -> some View {
        switch entity.kind {
        case .light:
            LightControls(entity: entity)
            if entity.isGroupLight { GroupMembersList(group: entity) }
        case .climate:
            // With heating helpers the automation owns the thermostat, so we change the helpers instead.
            if let areaId = store.resolvedAreas[entity.entityId], let room = store.rooms.first(where: { $0.id == areaId }), room.heating != nil {
                RoomHeatingDial(room: room)
                    .frame(maxWidth: .infinity)
            } else {
                ClimateControls(entity: entity)
            }
        case .cover: CoverControls(entity: entity)
        case .toggle: PowerButton(entity: entity)
        case .scene: SceneControls(entity: entity)
        case .sensor: SensorDetail(entity: entity)
        case .unsupported: EmptyView()
        }
    }
}

private struct DetailHeader: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity
    let room: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: entity.symbolName)
                .symbolVariant(entity.isActive ? .fill : .none)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(entity.isActive ? Color.white : Color.secondary)
                .frame(width: 68, height: 68)
                .background(Circle().fill(entity.isActive ? AnyShapeStyle(entity.tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
            Text(store.displayName(for: entity, inRoom: room))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text([room, entity.statusText].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(.snappy, value: entity.state)
    }
}

// MARK: - Power

private struct PowerButton: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity

    var body: some View {
        let isOn = entity.isActive
        Button {
            store.tap(entity)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 96, height: 96)
                .background(Circle().fill(isOn ? AnyShapeStyle(entity.tint.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Ausschalten" : "Einschalten")
        .animation(.snappy, value: isOn)
    }
}

// MARK: - Light

/// The individual lamps of a light group, so they stay reachable although the room only shows the group.
private struct GroupMembersList: View {
    @Environment(HomeStore.self) private var store
    let group: HAEntity

    var body: some View {
        let members = group.groupMembers.compactMap { store.entities[$0] }
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Einzelne Lampen").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                ForEach(members) { lamp in
                    LightTile(entity: lamp, name: lamp.displayName(inRoom: store.areaName(for: lamp.entityId)))
                }
            }
        }
    }
}

private struct LightControls: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity

    @State private var brightness: Double = 0
    @State private var temperature: Double = 0
    @State private var color: Color = .white
    @State private var isEditing = false

    private let presets: [Color] = [
        Color(red: 1, green: 0.62, blue: 0.27), Color(red: 1, green: 0.85, blue: 0.55), .red, .pink, .purple, .blue, .cyan, .green,
    ]

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .center, spacing: 32) {
                if entity.isDimmable {
                    BrightnessSlider(value: $brightness, tint: entity.tint, isEditing: $isEditing) {
                        sendBrightness()
                    }
                    .frame(width: 112, height: 260)
                }
                PowerButton(entity: entity)
            }

            if entity.supportsColorTemperature {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Farbtemperatur").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    GradientSlider(
                        value: $temperature,
                        gradient: Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.27), .white, Color(red: 0.75, green: 0.87, blue: 1)]),
                        isEditing: $isEditing
                    ) {
                        sendTemperature()
                    }
                }
            }

            if entity.supportsColor {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Farbe").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(presets.indices, id: \.self) { index in
                            Button {
                                color = presets[index]
                                sendColor(presets[index])
                            } label: {
                                Circle().fill(presets[index].gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("Eigene Farbe", selection: $color, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: color) { _, newColor in
                    if !presets.contains(newColor) { sendColor(newColor) }
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: entity) { _, _ in
            if !isEditing { sync() }
        }
    }

    private var kelvinRange: ClosedRange<Double> {
        let lower = entity.attributes["min_color_temp_kelvin"]?.double ?? 2000
        let upper = entity.attributes["max_color_temp_kelvin"]?.double ?? 6500
        return lower...max(upper, lower + 1)
    }

    private func sync() {
        brightness = Double(entity.brightnessPercent ?? 0) / 100
        if let kelvin = entity.attributes["color_temp_kelvin"]?.double {
            temperature = (kelvin - kelvinRange.lowerBound) / (kelvinRange.upperBound - kelvinRange.lowerBound)
        }
    }

    private func sendBrightness() {
        let percent = Int((brightness * 100).rounded())
        var predicted = entity
        if percent == 0 {
            predicted.state = "off"
            store.perform(.power(entityId: entity.entityId, on: false), predicted: predicted)
        } else {
            predicted.state = "on"
            predicted.attributes["brightness"] = .number(Double(percent) * 2.55)
            store.perform(
                ServiceCall(domain: "light", service: "turn_on", entityId: entity.entityId, data: ["brightness_pct": .number(Double(percent))]),
                predicted: predicted
            )
        }
    }

    private func sendTemperature() {
        let kelvin = kelvinRange.lowerBound + temperature * (kelvinRange.upperBound - kelvinRange.lowerBound)
        var predicted = entity
        predicted.state = "on"
        predicted.attributes["color_temp_kelvin"] = .number(kelvin.rounded())
        store.perform(
            ServiceCall(domain: "light", service: "turn_on", entityId: entity.entityId, data: ["color_temp_kelvin": .number(kelvin.rounded())]),
            predicted: predicted
        )
    }

    private func sendColor(_ color: Color) {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha) else { return }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        var predicted = entity
        predicted.state = "on"
        predicted.attributes["rgb_color"] = .array([.number(red * 255), .number(green * 255), .number(blue * 255)])
        store.perform(
            ServiceCall(
                domain: "light", service: "turn_on", entityId: entity.entityId,
                data: ["hs_color": .array([.number((hue * 360).rounded()), .number((saturation * 100).rounded())])]
            ),
            predicted: predicted
        )
    }
}

/// Tall Control-Center style slider; drag up/down relative to the start position.
private struct BrightnessSlider: View {
    @Binding var value: Double
    let tint: Color
    @Binding var isEditing: Bool
    let onCommit: () -> Void

    @State private var startValue: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color(.secondarySystemGroupedBackground))
                Rectangle()
                    .fill(tint.gradient)
                    .frame(height: geometry.size.height * value)
                Text("\(Int((value * 100).rounded())) %")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(value > 0.15 ? Color.black.opacity(0.7) : Color.secondary)
                    .padding(.bottom, 16)
                    .contentTransition(.numericText())
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isEditing = true
                        let start = startValue ?? value
                        startValue = start
                        value = min(1, max(0, start - drag.translation.height / geometry.size.height))
                    }
                    .onEnded { _ in
                        startValue = nil
                        isEditing = false
                        Haptics.tap()
                        onCommit()
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Helligkeit")
        .accessibilityValue("\(Int((value * 100).rounded())) Prozent")
        .accessibilityAdjustableAction { direction in
            value = min(1, max(0, value + (direction == .increment ? 0.1 : -0.1)))
            onCommit()
        }
    }
}

/// Horizontal slider drawn on a colour gradient.
private struct GradientSlider: View {
    @Binding var value: Double
    let gradient: Gradient
    @Binding var isEditing: Bool
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let knob: CGFloat = 36
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: 4 + (geometry.size.width - knob - 8) * value)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isEditing = true
                        value = min(1, max(0, (drag.location.x - knob / 2) / (geometry.size.width - knob)))
                    }
                    .onEnded { _ in
                        isEditing = false
                        Haptics.tap()
                        onCommit()
                    }
            )
        }
        .frame(height: 44)
    }
}

// MARK: - Climate

private struct ClimateControls: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity

    @State private var target: Double = 20
    @State private var sendTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(target.formatted(.number.precision(.fractionLength(1))) + "°")
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: target))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 48) {
                stepButton(symbol: "minus", delta: -entity.temperatureStep)
                stepButton(symbol: "plus", delta: entity.temperatureStep)
            }

            if entity.hvacModes.count > 1 {
                Picker("Modus", selection: Binding(get: { entity.state }, set: { setMode($0) })) {
                    ForEach(entity.hvacModes, id: \.self) { mode in
                        Text(HAEntity.hvacModeName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear { target = entity.targetTemperature ?? target }
        .onChange(of: entity.targetTemperature) { _, newValue in
            if sendTask == nil, let newValue { target = newValue }
        }
    }

    private var subtitle: String {
        var parts = ["Zieltemperatur"]
        if let current = entity.currentTemperature { parts.append("aktuell \(HAEntity.formatTemperature(current))") }
        if entity.hvacAction == "heating" { parts.append("heizt") }
        return parts.joined(separator: " · ")
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        Button {
            withAnimation(.snappy) {
                target = min(entity.maxTemperature, max(entity.minTemperature, target + delta))
            }
            Haptics.tap()
            scheduleSend()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Wärmer" : "Kälter")
    }

    /// Waits briefly so several taps result in a single command.
    private func scheduleSend() {
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            var predicted = entity
            predicted.attributes["temperature"] = .number(target)
            store.perform(
                ServiceCall(domain: "climate", service: "set_temperature", entityId: entity.entityId, data: ["temperature": .number(target)]),
                predicted: predicted
            )
            sendTask = nil
        }
    }

    private func setMode(_ mode: String) {
        var predicted = entity
        predicted.state = mode
        store.perform(
            ServiceCall(domain: "climate", service: "set_hvac_mode", entityId: entity.entityId, data: ["hvac_mode": .string(mode)]),
            predicted: predicted
        )
    }
}

// MARK: - Cover

private struct CoverControls: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity

    @State private var position: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 20) {
                coverButton("Öffnen", symbol: "chevron.up", service: "open_cover", predictedState: "opening")
                coverButton("Stopp", symbol: "stop.fill", service: "stop_cover", predictedState: nil)
                coverButton("Schließen", symbol: "chevron.down", service: "close_cover", predictedState: "closing")
            }
            if entity.coverPosition != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position · \(Int(position * 100)) %")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    GradientSlider(
                        value: $position,
                        gradient: Gradient(colors: [Color.indigo.opacity(0.35), Color.indigo]),
                        isEditing: $isEditing
                    ) {
                        sendPosition()
                    }
                }
            }
        }
        .onAppear { position = Double(entity.coverPosition ?? 0) / 100 }
        .onChange(of: entity.coverPosition) { _, newValue in
            if !isEditing { position = Double(newValue ?? 0) / 100 }
        }
    }

    private func coverButton(_ title: String, symbol: String, service: String, predictedState: String?) -> some View {
        Button {
            Haptics.tap()
            var predicted = entity
            if let predictedState { predicted.state = predictedState }
            store.perform(
                ServiceCall(domain: "cover", service: service, entityId: entity.entityId),
                predicted: predictedState == nil ? nil : predicted
            )
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                Text(title).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sendPosition() {
        let percent = Int((position * 100).rounded())
        var predicted = entity
        predicted.attributes["current_position"] = .number(Double(percent))
        predicted.state = percent == 0 ? "closed" : "open"
        store.perform(
            ServiceCall(domain: "cover", service: "set_cover_position", entityId: entity.entityId, data: ["position": .number(Double(percent))]),
            predicted: predicted
        )
    }
}

// MARK: - Scene & sensor

private struct SceneControls: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity

    var body: some View {
        Button {
            store.tap(entity)
        } label: {
            Label(entity.domain == "script" ? "Ausführen" : "Aktivieren", systemImage: entity.symbolName)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(entity.tint)
        .buttonBorderShape(.capsule)
    }
}

private struct SensorDetail: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity
    @State private var history: [StateChange]?

    private var isNumeric: Bool { Double(entity.state) != nil }

    var body: some View {
        VStack(spacing: 8) {
            Text(entity.sensorValueText)
                .font(.system(size: 56, weight: .light, design: .rounded))
                .contentTransition(.numericText())
                .multilineTextAlignment(.center)
            if let changed = lastChanged {
                Text("Geändert \(changed, format: .relative(presentation: .named))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if entity.domain == "sensor" {
                SensorHistoryCard(entity: entity, history: history, isNumeric: isNumeric)
                    .padding(.top, 16)
            }
        }
        .task(id: entity.entityId) {
            let loaded = (try? await store.stateHistory(of: [entity.entityId], hours: 24))?[entity.entityId] ?? []
            withAnimation(.easeOut(duration: 0.35)) { history = loaded }
        }
    }

    private var lastChanged: Date? {
        guard let text = entity.lastChanged else { return nil }
        return (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)))
            ?? (try? Date(text, strategy: .iso8601))
    }
}

/// The last 24 hours of a sensor in a card of fixed height, so nothing jumps while it loads.
private struct SensorHistoryCard: View {
    let entity: HAEntity
    /// `nil` while loading.
    let history: [StateChange]?
    let isNumeric: Bool

    /// Where the finger is on the chart; shows the value at that time.
    @State private var selectedDate: Date?

    private static let chartHeight: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Letzte 24 Stunden")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                selectionLabel
            }
            ZStack {
                if let history {
                    if isNumeric { numericChart(history) } else { stateTimeline(history) }
                } else {
                    // Placeholder while loading: a faint baseline instead of a spinner.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: isNumeric ? Self.chartHeight : 76)
            .transition(.opacity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        #if DEBUG
        .onAppear {
            // `ZUHAUSE_DEBUG_CHART_HOURS_AGO`: preselects a point in the chart (for screenshots).
            if let hours = ProcessInfo.processInfo.environment["ZUHAUSE_DEBUG_CHART_HOURS_AGO"].flatMap(Double.init) {
                selectedDate = .now.addingTimeInterval(-hours * 3600)
            }
        }
        #endif
    }

    /// Value and time under the finger, or a hint how to get there.
    @ViewBuilder
    private var selectionLabel: some View {
        if let selectedDate, let value = value(at: selectedDate) {
            HStack(spacing: 6) {
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(selectedDate, format: .dateTime.hour().minute()).font(.subheadline).foregroundStyle(.secondary)
            }
            .monospacedDigit()
        } else {
            Text(history?.isEmpty == false ? "Antippen für Wert" : " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The state that was valid at a time: the last change before it.
    private func value(at date: Date) -> String? {
        guard let history else { return nil }
        let changes = history.filter { $0.state != "unavailable" && $0.state != "unknown" }
        if isNumeric {
            // For numbers the closest reading, like the point on the curve.
            guard let closest = changes.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                  let number = Double(closest.state) else { return nil }
            var reading = entity
            reading.state = String(number)
            return reading.sensorValueText
        }
        guard let change = changes.last(where: { $0.date <= date }) ?? changes.first else { return nil }
        return HAEntity.translatedState(change.state)
    }

    // MARK: Numbers

    @ViewBuilder
    private func numericChart(_ history: [StateChange]) -> some View {
        let points = history.compactMap { change in Double(change.state).map { HistoryPoint(date: change.date, value: $0) } }
        if points.count > 1, let low = points.map(\.value).min(), let high = points.map(\.value).max() {
            // Some room above and below the curve, so small changes stay visible without exaggerating noise.
            let padding = max((high - low) * 0.25, 0.5)
            let domain = (low - padding)...(high + padding)
            let selected = selectedDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
            Chart {
                ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Zeit", point.date), yStart: .value("Wert", domain.lowerBound), yEnd: .value("Wert", point.value))
                    .foregroundStyle(LinearGradient(colors: [entity.tint.opacity(0.25), entity.tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Zeit", point.date), y: .value("Wert", point.value))
                    .foregroundStyle(entity.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
                if let selected {
                    RuleMark(x: .value("Zeit", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("Zeit", selected.date), y: .value("Wert", selected.value))
                        .foregroundStyle(entity.tint)
                        .symbolSize(90)
                    PointMark(x: .value("Zeit", selected.date), y: .value("Wert", selected.value))
                        .foregroundStyle(.white)
                        .symbolSize(25)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: domain)
            .chartXScale(domain: Date.now.addingTimeInterval(-24 * 3600)...Date.now)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { AxisGridLine(); AxisValueLabel() } }
        } else {
            noData
        }
    }

    // MARK: Text states (air quality …)

    private struct Segment: Identifiable {
        let id: Date
        let end: Date
        let state: String
    }

    @ViewBuilder
    private func stateTimeline(_ history: [StateChange]) -> some View {
        let start = Date.now.addingTimeInterval(-24 * 3600)
        let changes = history.filter { $0.state != "unavailable" && $0.state != "unknown" }
        let segments = changes.indices.map { index in
            Segment(id: max(changes[index].date, start),
                    end: index + 1 < changes.count ? changes[index + 1].date : .now,
                    state: changes[index].state)
        }
        if segments.isEmpty {
            noData
        } else {
            let states = segments.map(\.state).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            Chart {
                ForEach(segments) { segment in
                    RectangleMark(xStart: .value("Von", segment.id), xEnd: .value("Bis", segment.end), y: .value("", ""), height: 28)
                        .foregroundStyle(by: .value("Zustand", HAEntity.translatedState(segment.state)))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if let selectedDate {
                    RuleMark(x: .value("Zeit", selectedDate))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartForegroundStyleScale(domain: states.map(HAEntity.translatedState), range: states.map(Self.color(for:)))
            .chartXScale(domain: start...Date.now)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }

    private static func color(for state: String) -> Color {
        switch state {
        case "excellent": .green
        case "good": .mint
        case "moderate", "fair": .yellow
        case "poor": .orange
        case "unhealthy", "very_poor", "extremely_poor": .red
        case "on": .teal
        default: .gray
        }
    }

    private var noData: some View {
        Text("Keine Daten")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
