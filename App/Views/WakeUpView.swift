import SwiftUI

/// One room taking part in the morning warm-up, with its estimated start.
private struct WakePlan: Identifiable {
    let room: Room
    let heating: RoomHeating
    /// Minutes before the wake-up time; `nil` if the room is already set at least as warm as its morning temperature
    /// (then "Heizung: Vor dem Aufstehen aufwärmen" leaves it alone, whatever its mode).
    let lead: Int?

    var id: String { room.id }

    @MainActor
    static func all(in store: HomeStore) -> [WakePlan] {
        store.rooms.compactMap { room in
            guard let heating = room.heating, heating.wakeTemperature != nil else { return nil }
            let alreadyWarm = heating.targetValue.flatMap { target in heating.wakeTemperatureValue.map { target >= $0 } } ?? false
            let lead = alreadyWarm ? nil : heating.warmupLead(from: room.currentTemperature)
            return WakePlan(room: room, heating: heating, lead: lead)
        }
    }
}

/// Morning warm-up: when it should be warm and how warm each room gets.
/// The timing and the learning run in HA ("Heizung: Vor dem Aufstehen aufwärmen", "Heizung: Aufheizzeit messen").
struct WakeUpView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let settings = store.heatingSettings
        let plans = WakePlan.all(in: store)
        let isOn = settings.morningWarmup?.state == "on"
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WakeTimeCard(settings: settings)

                Group {
                    if let wake = settings.wakeMinutes {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Ablauf", symbol: "chart.bar.xaxis")
                            WakeTimeline(plans: plans.filter(\.heating.isWakeEnabled), wakeMinutes: wake)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Räume", symbol: "square.split.2x2.fill")
                        ForEach(plans) { plan in WakeRoomCard(plan: plan) }
                    }
                }
                .opacity(isOn ? 1 : 0.45)
                .animation(.snappy, value: isOn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Morgens aufwärmen")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func timeBinding(_ entity: HAEntity, store: HomeStore) -> Binding<Date> {
        Binding(
            get: {
                let hour = entity.attributes["hour"]?.int ?? 7
                let minute = entity.attributes["minute"]?.int ?? 0
                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.setTime(entity, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}

/// On/off and the large wake-up time; tapping the time opens a wheel.
private struct WakeTimeCard: View {
    @Environment(HomeStore.self) private var store
    let settings: HeatingSettings
    @State private var isPickingTime = false

    var body: some View {
        let isOn = settings.morningWarmup?.state == "on"
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                Text("Warm um")
                    .font(.headline)
                Spacer()
                if let master = settings.morningWarmup {
                    Toggle("Morgens aufwärmen", isOn: Binding(get: { isOn }, set: { _ in store.tap(master) }))
                        .labelsHidden()
                        .tint(.orange)
                }
            }

            if let wakeTime = settings.wakeTime, let minutes = settings.wakeMinutes {
                Button {
                    Haptics.tap()
                    isPickingTime.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(HeatingSettings.clock(minutes))
                            .font(.system(size: 60, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(isOn ? Color.primary : Color.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isPickingTime ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Warm um \(HeatingSettings.clock(minutes))")
                .accessibilityHint("Zeit ändern")

                if isPickingTime {
                    DatePicker("Warm um", selection: WakeUpView.timeBinding(wakeTime, store: store), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.orange.opacity(isOn ? 0.08 : 0)))
        )
        .animation(.snappy, value: isPickingTime)
        .animation(.snappy, value: isOn)
    }
}

/// When each room starts heating, as bars that all end at the wake-up time.
private struct WakeTimeline: View {
    let plans: [WakePlan]
    let wakeMinutes: Int

    var body: some View {
        // Round the visible span up to whole half hours, at least one hour.
        let longest = plans.compactMap(\.lead).max() ?? 0
        let span = max(60, Int((Double(longest) / 30).rounded(.up)) * 30)
        VStack(spacing: 12) {
            if plans.isEmpty {
                Label("Kein Raum ausgewählt", systemImage: "bed.double")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(plans) { plan in
                    HStack(spacing: 10) {
                        Image(systemName: plan.room.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        bar(plan, span: span)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(plan.room.name)
                    .accessibilityValue(plan.lead.map { "Start \(HeatingSettings.clock(wakeMinutes - $0))" } ?? "Schon warm eingestellt")
                }
                HStack {
                    Text(HeatingSettings.clock(wakeMinutes - span))
                    Spacer()
                    Label(HeatingSettings.clock(wakeMinutes), systemImage: "sunrise.fill")
                        .foregroundStyle(.orange)
                }
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .animation(.snappy, value: plans.map(\.lead))
    }

    private func bar(_ plan: WakePlan, span: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                if let lead = plan.lead {
                    let width = max(56, geo.size.width * CGFloat(lead) / CGFloat(span))
                    Capsule()
                        .fill(Color.orange.gradient)
                        .frame(width: width)
                        .overlay(alignment: .leading) {
                            Text(HeatingSettings.clock(wakeMinutes - lead))
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.leading, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Label("Schon warm eingestellt", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
            }
        }
        .frame(height: 28)
    }
}

/// One room: whether it takes part, how warm it gets and how well its heating time is learned.
private struct WakeRoomCard: View {
    @Environment(HomeStore.self) private var store
    let plan: WakePlan

    var body: some View {
        let heating = plan.heating
        let isEnabled = heating.isWakeEnabled
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: plan.room.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isEnabled ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.room.name).font(.headline)
                    if isEnabled { LearningBadge(heating: heating) }
                }
                Spacer()
                if let enabled = heating.wakeEnabled {
                    Toggle(plan.room.name, isOn: Binding(get: { isEnabled }, set: { _ in store.tap(enabled) }))
                        .labelsHidden()
                        .tint(.orange)
                }
            }

            if isEnabled, let temperature = heating.wakeTemperature {
                HStack(spacing: 10) {
                    if let current = plan.room.currentTemperature {
                        Label(Self.degrees(current), systemImage: "thermometer.medium")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    ValueStepper(
                        value: Double(temperature.state),
                        step: temperature.attributes["step"]?.double ?? 0.5,
                        range: (temperature.attributes["min"]?.double ?? 7)...(temperature.attributes["max"]?.double ?? 30),
                        format: Self.degrees,
                        onCommit: { store.setValue(temperature, to: $0) }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.orange.opacity(isEnabled ? 0.06 : 0)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: isEnabled)
    }

    private static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }
}

/// How far the heating time of a room has been learned: an estimate, still learning, or settled.
private struct LearningBadge: View {
    let heating: RoomHeating

    /// From this many measured mornings on, the value counts as learned.
    private static let settledAfter = 3

    var body: some View {
        let count = heating.learnedCount
        let (title, symbol, tint): (String, String, Color) = switch count {
        case 0: ("Schätzung", "wand.and.sparkles", .secondary)
        case ..<Self.settledAfter: ("Lernt", "graduationcap.fill", .blue)
        default: ("Eingelernt", "checkmark.seal.fill", .green)
        }
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(title) · \(Int(heating.minutesPerDegree)) min/°")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count == 0 ? "Aufheizzeit geschätzt" : "Aufheizzeit aus \(count) Morgen gelernt")
    }
}

/// Overview card: wake-up time at a glance, switch on/off, tap for the details.
struct WakeUpCard: View {
    @Environment(HomeStore.self) private var store
    @State private var isShowingDetails = false

    var body: some View {
        let settings = store.heatingSettings
        if let master = settings.morningWarmup, let wakeMinutes = settings.wakeMinutes {
            let isOn = master.state == "on"
            let plans = WakePlan.all(in: store).filter(\.heating.isWakeEnabled)
            let firstStart = plans.compactMap(\.lead).max().map { HeatingSettings.clock(wakeMinutes - $0) }
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color(.tertiarySystemFill))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOn ? "Warm um \(HeatingSettings.clock(wakeMinutes))" : "Morgens aufwärmen")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    HStack(spacing: 4) {
                        if isOn, let firstStart {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                            Text("ab \(firstStart)").monospacedDigit()
                            ForEach(plans) { plan in
                                Image(systemName: plan.room.symbol)
                            }
                            .padding(.leading, 2)
                        } else {
                            Text(isOn ? "Kein Raum ausgewählt" : "Aus")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Toggle("Morgens aufwärmen", isOn: Binding(get: { isOn }, set: { _ in store.tap(master) }))
                    .labelsHidden()
                    .tint(.orange)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.orange.opacity(isOn ? 0.08 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture { isShowingDetails = true }
            .animation(.snappy, value: isOn)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Einstellen") { isShowingDetails = true }
            .sheet(isPresented: $isShowingDetails) {
                NavigationStack {
                    WakeUpView()
                        .toolbar {
                            Button("Fertig") { isShowingDetails = false }
                        }
                }
            }
            #if DEBUG
            .task {
                guard ProcessInfo.processInfo.environment["ZUHAUSE_DEBUG_WAKEUP"] == "1" else { return }
                try? await Task.sleep(for: .seconds(1))
                isShowingDetails = true
            }
            #endif
        }
    }
}
