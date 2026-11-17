import SwiftUI

/// Rounded card with a coloured header, used for the sections of a room (Licht, Heizung, Raumklima …).
struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(_ title: String, symbol: String, tint: Color,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.gradient))
                Text(title).font(.title3.weight(.bold))
                Spacer()
                accessory()
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(tint.opacity(0.06)))
        )
    }
}

/// Small capsule button for section headers ("Alle aus").
struct PillButton: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

/// Light tile: tap toggles, long press opens details, slider sets the brightness.
struct LightTile: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity
    let name: String

    @State private var brightness: Double = 0
    @State private var isEditing = false

    var body: some View {
        let isOn = entity.state == "on"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: entity.isGroupLight ? "lightbulb.2" : "lightbulb")
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isOn ? AnyShapeStyle(entity.tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(isEditing ? "\(Int(brightness * 100)) %" : entity.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isFavorite(entity.entityId) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .contentShape(Rectangle())
            .tileGestures(
                onTap: { store.tap(entity) },
                onLongPress: { store.showDetail(entity.entityId) }
            )

            if entity.isDimmable {
                Slider(value: $brightness, in: 0...1) { editing in
                    isEditing = editing
                    if !editing { commitBrightness() }
                }
                .tint(isOn ? entity.tint : Color.secondary)
                .disabled(entity.isUnavailable)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(entity.tint.opacity(isOn ? 0.18 : 0)))
        )
        .opacity(entity.isUnavailable ? 0.5 : 1)
        .animation(.snappy, value: entity.state)
        .onAppear(perform: sync)
        .onChange(of: entity) { _, _ in if !isEditing { sync() } }
    }

    private func sync() {
        brightness = Double(entity.brightnessPercent ?? 0) / 100
    }

    private func commitBrightness() {
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
        Haptics.tap()
    }
}

/// Small sensor tile with a traffic-light dot for air quality values.
struct SensorTile: View {
    @Environment(HomeStore.self) private var store
    let entity: HAEntity
    let name: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entity.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(entity.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.sensorValueText)
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let rating = entity.airRating {
                Circle()
                    .fill([Color.green, .orange, .red][rating])
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(["Gut", "Mittel", "Schlecht"][rating])
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { store.showDetail(entity.entityId) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Apple Home scene button in a grid; a tap runs the scene via HomeKit.
struct SceneButton: View {
    @Environment(AppleHomeScenes.self) private var appleScenes
    let scene: AppleScene

    var body: some View {
        let highlighted = appleScenes.recentlyRun.contains(scene.id)
        let tint = Color.purple
        Button { appleScenes.run(scene) } label: {
            HStack(spacing: 8) {
                Image(systemName: scene.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(highlighted ? Color.white : tint)
                Text(scene.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(highlighted ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: highlighted)
    }
}

/// Grid of Apple Home scenes, used on room pages and the overview.
struct SceneGrid: View {
    let scenes: [AppleScene]
    var body: some View {
        TileGrid(spacing: 8) {
            ForEach(scenes) { SceneButton(scene: $0) }
        }
    }
}

/// − value + control that waits briefly before sending, so several taps become one command.
struct ValueStepper: View {
    let value: Double?
    let step: Double
    let range: ClosedRange<Double>
    var large = false
    let format: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draft: Double?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        let shown = draft ?? value
        HStack(spacing: large ? 28 : 14) {
            button("minus", delta: -step)
            Text(shown.map(format) ?? "–")
                .font(large ? .system(size: 44, weight: .light, design: .rounded) : .title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: shown ?? 0))
                .frame(minWidth: large ? 120 : 70)
            button("plus", delta: step)
        }
        .animation(.snappy, value: shown)
    }

    private func button(_ symbol: String, delta: Double) -> some View {
        Button {
            guard let current = draft ?? value else { return }
            let next = min(range.upperBound, max(range.lowerBound, current + delta))
            draft = next
            Haptics.tap()
            commitTask?.cancel()
            commitTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                onCommit(next)
                // Keep the draft until HA confirms, so the number does not jump back.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                draft = nil
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: large ? 22 : 16, weight: .bold))
                .frame(width: large ? 60 : 40, height: large ? 60 : 40)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Erhöhen" : "Verringern")
    }
}

/// Komfort / Nacht / Abwesend as large segmented buttons. "Manuell" only appears (not tappable)
/// while the room was turned by hand.
struct HeatingModePicker: View {
    let options: [String]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    Haptics.tap()
                    onSelect(option)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: Self.symbol(for: option)).font(.body.weight(.semibold))
                        Text(Self.label(for: option)).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(Self.tint(for: option).gradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if selection == RoomHeating.manualMode {
                VStack(spacing: 4) {
                    Image(systemName: Self.symbol(for: RoomHeating.manualMode)).font(.body.weight(.semibold))
                    Text(RoomHeating.manualMode).font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Self.tint(for: RoomHeating.manualMode).gradient)
                )
                .transition(.scale.combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
                .accessibilityHint("Von Hand eingestellt. Wähle einen Modus, um zur festen Temperatur zurückzukehren.")
            }
        }
        .animation(.snappy, value: selection)
    }

    static func label(for mode: String) -> String {
        mode == "Komfort" ? "Normal" : mode
    }

    static func symbol(for mode: String) -> String {
        switch mode {
        case "Komfort": "flame.fill"
        case "Nacht": "moon.fill"
        case "Abwesend": "figure.walk.departure"
        case "Manuell": "hand.raised.fill"
        default: "thermometer.medium"
        }
    }

    static func tint(for mode: String) -> Color {
        switch mode {
        case "Komfort": .orange
        case "Nacht": .indigo
        case "Abwesend": .gray
        default: .teal
        }
    }
}

/// "Alle Nacht / Alle Abwesend / Alle aufwärmen" like on the dashboard.
struct HeatingQuickActions: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let modes = store.heatingModes
        if !modes.isEmpty {
            HStack(spacing: 8) {
                action("Alle Nacht", option: "Nacht", modes: modes)
                action("Alle Abwesend", option: "Abwesend", modes: modes)
                action("Alle aufwärmen", option: "Komfort", modes: modes)
            }
        }
    }

    private func action(_ title: String, option: String, modes: [HAEntity]) -> some View {
        let isActive = modes.allSatisfy { $0.state == option }
        let tint = HeatingModePicker.tint(for: option)
        return Button {
            store.setAllHeatingModes(option)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: HeatingModePicker.symbol(for: option)).font(.title3)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(isActive ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Top of a room page: the current room temperature, large, with the humidity next to it.
/// Tapping either opens the sensor with its 24-h history.
struct RoomClimateHeader: View {
    @Environment(HomeStore.self) private var store
    let room: Room

    var body: some View {
        if room.currentTemperature != nil || room.humidity != nil {
            // Label and humidity centred next to the large number rather than hanging from its baseline.
            HStack(alignment: .center, spacing: 14) {
                if let current = room.currentTemperature {
                    Text(TemperatureDial.format(current))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: current))
                        .onTapGesture { open(room.temperature) }
                        .accessibilityAddTraits(room.temperature != nil ? .isButton : [])
                        .accessibilityHint(room.temperature != nil ? "Zeigt den Verlauf der letzten 24 Stunden" : "")
                }
                VStack(alignment: .leading, spacing: 4) {
                    if room.currentTemperature != nil {
                        Text("Im Raum").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if let humidity = room.humidity {
                        Label(humidity.sensorValueText, systemImage: "humidity")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.teal)
                            .monospacedDigit()
                            .onTapGesture { open(humidity) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .animation(.snappy, value: room.currentTemperature)
        }
    }

    private func open(_ sensor: HAEntity?) {
        guard let sensor else { return }
        Haptics.tap()
        store.showDetail(sensor.entityId)
    }
}

/// Compact heating tile in a room; tapping opens the dial.
struct HeatingTile: View {
    let room: Room
    let heating: RoomHeating
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: room.isHeating ? "flame.fill" : "heater.vertical.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.orange.gradient))
                    .symbolEffect(.pulse, options: .repeating, isActive: room.isHeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heizung").font(.headline).foregroundStyle(.primary)
                    Text(room.isHeating ? "Heizt" : heating.mode.map { HeatingModePicker.label(for: $0.state) } ?? "Soll-Temperatur")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(heating.targetValue.map(TemperatureDial.format) ?? "–")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(heating.mode.map { HeatingModePicker.tint(for: $0.state) } ?? .orange)
                    .contentTransition(.numericText(value: heating.targetValue ?? 0))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.orange.opacity(0.08)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: heating.targetValue)
    }
}

/// The heater fans of a room: plug on/off in the header, speed slider and the automation switch.
struct HeaterFanCard: View {
    @Environment(HomeStore.self) private var store
    let fan: RoomFan

    @State private var speed: Double = 0
    @State private var isEditing = false

    var body: some View {
        let tint = Color.cyan
        SectionCard("Heizungslüfter", symbol: "fan.fill", tint: tint) {
            if let power = fan.power {
                Toggle("Steckdose", isOn: Binding(get: { fan.isPowered }, set: { store.setFanPower(fan, on: $0) }))
                    .labelsHidden()
                    .tint(tint)
                    .disabled(power.isUnavailable)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "fan")
                        .symbolVariant(fan.isRunning ? .fill : .none)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(fan.isRunning ? Color.white : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(fan.isRunning ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                        .symbolEffect(.pulse, options: .repeating, isActive: fan.isRunning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isEditing ? "Stufe \(Int(speed.rounded())) %" : fan.statusText)
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if fan.demand != nil {
                            Text(fan.needsHeat ? "Raum braucht Wärme" : "Raum warm genug")
                                .font(.subheadline)
                                .foregroundStyle(fan.needsHeat ? Color.orange : Color.secondary)
                        }
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $speed, in: fan.speedRange, step: fan.speedStep) { editing in
                        isEditing = editing
                        if !editing, abs(speed - fan.speedValue) >= 0.5 { store.setFanSpeed(fan, to: speed) }
                    }
                    .tint(tint)
                    .disabled(fan.power?.isUnavailable == true)
                    .accessibilityLabel("Lüfterstufe")
                    .accessibilityValue("\(Int(speed.rounded())) Prozent")
                    HStack {
                        Text("Halten").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(fan.speedRange.upperBound)) %").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if fan.automation != nil {
                    Divider()
                    Toggle(isOn: Binding(get: { fan.isAutomatic }, set: { store.setFanAutomatic(fan, on: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatik").font(.subheadline.weight(.semibold))
                            Text(fan.isAutomatic
                                 ? "Stufe nach Wärmebedarf und Licht. Von Hand Geändertes gilt bis zur nächsten Änderung."
                                 : "Aus: Stufe und Steckdose bleiben, wie du sie stellst.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(tint)
                }
            }
        }
        .opacity(fan.power?.isUnavailable == true ? 0.6 : 1)
        .animation(.snappy, value: fan.speedValue)
        .animation(.snappy, value: fan.isPowered)
        .onAppear { speed = fan.speedValue }
        .onChange(of: fan.speedValue) { _, value in if !isEditing { speed = value } }
    }
}

/// Full-height sheet with a large dial for the Wunschtemperatur, like the climate control in Apple Home.
struct HeatingSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let roomId: String

    var body: some View {
        let room = store.rooms.first { $0.id == roomId }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: room?.isHeating == true ? "flame.fill" : "heater.vertical.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(room?.name ?? "").font(.title3.weight(.bold))
                    Text(room?.isHeating == true ? "Heizt" : "Heizung")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schließen")
            }

            Spacer()

            if let room { RoomHeatingDial(room: room, diameter: 300) }

            Spacer()

            if let room, !room.thermostats.isEmpty {
                VStack(spacing: 8) {
                    ForEach(room.thermostats) { thermostat in
                        ThermostatInfoRow(thermostat: thermostat, name: store.displayName(for: thermostat, inRoom: room.name))
                    }
                }
            }

            if let heating = room?.heating, let mode = heating.mode, !heating.modeOptions.isEmpty {
                VStack(spacing: 8) {
                    HeatingModePicker(options: heating.modeOptions, selection: mode.state) { store.selectHeatingMode(heating, $0) }
                }
                .padding(.top, 12)
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationCornerRadius(36)
        .presentationBackground {
            LinearGradient(
                colors: [Color.orange.opacity(0.22), Color(.systemBackground).opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .background(.regularMaterial)
        }
    }
}

/// One thermostat under the dial: how far the valve is open, what it is set to and what it measures.
private struct ThermostatInfoRow: View {
    @Environment(HomeStore.self) private var store
    let thermostat: HAEntity
    let name: String

    var body: some View {
        let heating = thermostat.hvacAction == "heating"
        VStack(alignment: .leading, spacing: 10) {
            Label(name, systemImage: heating ? "flame.fill" : "heater.vertical")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(heating ? Color.orange : Color.primary)
            if thermostat.isUnavailable || thermostat.state == "off" {
                Text(thermostat.isUnavailable ? "Nicht erreichbar" : "Aus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    if let valve = store.valvePosition(of: thermostat) {
                        value(valve <= 0 ? "zu" : "\(Int(valve.rounded())) %", label: "Ventil offen")
                    }
                    if let target = thermostat.targetTemperature {
                        value(TemperatureDial.format(target), label: "Ventil gestellt")
                    }
                    if let current = thermostat.currentTemperature {
                        value(TemperatureDial.format(current), label: "Misst")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(thermostat.isUnavailable ? 0.5 : 1)
    }

    private func value(_ text: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The dial wired to a room's Wunschtemperatur helper.
struct RoomHeatingDial: View {
    @Environment(HomeStore.self) private var store
    let room: Room
    var diameter: CGFloat = 250

    var body: some View {
        if let heating = room.heating {
            // Changing it by hand only changes this room until the next mode switch; the fixed temperatures stay.
            TemperatureDial(
                current: room.currentTemperature,
                target: heating.targetValue,
                step: heating.target.attributes["step"]?.double ?? 0.5,
                range: (heating.target.attributes["min"]?.double ?? 7)...(heating.target.attributes["max"]?.double ?? 30),
                diameter: diameter,
                onCommit: { store.setTargetByHand(heating, to: $0) }
            )
        }
    }
}

/// Round dial like in Apple Home: grab the white knob and drag it along the ring to set the Wunschtemperatur.
struct TemperatureDial: View {
    let current: Double?
    let target: Double?
    let step: Double
    let range: ClosedRange<Double>
    var diameter: CGFloat = 250
    let onCommit: (Double) -> Void

    @State private var draft: Double?
    @State private var isDragging = false
    /// Set when a drag started away from the knob, so it is ignored until the finger lifts.
    @State private var isIgnoringDrag = false
    @State private var clearTask: Task<Void, Never>?

    private var lineWidth: CGFloat { diameter * 0.12 }
    /// The ring starts bottom left and runs clockwise over 270° to bottom right.
    private let startAngle = 135.0
    private let sweep = 270.0

    var body: some View {
        let shown = draft ?? target
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = (size - lineWidth) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ring(Color(.tertiarySystemFill), to: 1)
                if let shown {
                    ring(AngularGradient(colors: [.orange.opacity(0.7), .orange, .red], center: .center,
                                         startAngle: .zero, endAngle: .degrees(sweep)),
                         to: fraction(of: shown))
                }
                if let current {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .position(point(for: fraction(of: current), center: center, radius: radius))
                        .accessibilityHidden(true)
                }
                if let shown {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: lineWidth - 4, height: lineWidth - 4)
                        .scaleEffect(isDragging ? 1.15 : 1)
                        .position(point(for: fraction(of: shown), center: center, radius: radius))
                }
                VStack(spacing: 4) {
                    Text(shown.map(Self.format) ?? "–")
                        .font(.system(size: diameter * 0.24, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: shown ?? 0))
                    if let current {
                        Text("Im Raum \(HAEntity.formatTemperature(current))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Circle().inset(by: lineWidth / 2).stroke(lineWidth: lineWidth * 2))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging && !isIgnoringDrag {
                            guard let shown else { isIgnoringDrag = true; return }
                            let knob = point(for: fraction(of: shown), center: center, radius: radius)
                            // Generous hit area around the knob so it is easy to grab (at least 44pt).
                            let hitRadius = max(lineWidth, 22)
                            guard hypot(drag.startLocation.x - knob.x, drag.startLocation.y - knob.y) <= hitRadius else {
                                isIgnoringDrag = true
                                return
                            }
                        }
                        guard !isIgnoringDrag else { return }
                        clearTask?.cancel()
                        isDragging = true
                        draft = value(at: drag.location, center: center, previous: draft ?? target)
                    }
                    .onEnded { _ in
                        isIgnoringDrag = false
                        guard isDragging else { return }
                        isDragging = false
                        if let draft { commit(draft) }
                    }
            )
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy, value: shown)
        .animation(.snappy, value: isDragging)
        .sensoryFeedback(.selection, trigger: draft) { old, new in old != nil && new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Soll-Temperatur")
        .accessibilityValue(shown.map(Self.format) ?? "–")
        .accessibilityAdjustableAction { direction in
            guard let base = draft ?? target else { return }
            let next = clamp(base + (direction == .increment ? step : -step))
            draft = next
            commit(next)
        }
    }

    private func ring<S: ShapeStyle>(_ style: S, to fraction: Double) -> some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: sweep / 360 * fraction)
            .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(startAngle))
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (value - range.lowerBound) / span)) : 0
    }

    private func point(for fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Angle.degrees(startAngle + sweep * fraction).radians
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Temperature under the finger, rounded to `step`. In the gap at the bottom it sticks to the nearer end,
    /// and it never jumps from one end of the scale to the other.
    private func value(at location: CGPoint, center: CGPoint, previous: Double?) -> Double {
        let degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        var relative = (degrees - startAngle).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        if relative > sweep { relative = relative < sweep + (360 - sweep) / 2 ? sweep : 0 }
        var fraction = relative / sweep
        if let previous {
            let last = self.fraction(of: previous)
            if abs(fraction - last) > 0.5 { fraction = last > 0.5 ? 1 : 0 }
        }
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return clamp((raw / step).rounded() * step)
    }

    private func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private func commit(_ value: Double) {
        if value != target { onCommit(value) }
        // Keep the draft until HA confirms, so the number does not jump back.
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            draft = nil
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }
}
