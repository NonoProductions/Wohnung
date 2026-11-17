import Foundation

struct HAArea: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let icon: String?
}

/// A room as shown in the app: one HA area, organised like the "Zuhause" dashboard.
struct Room: Identifiable {
    let id: String
    let name: String
    let symbol: String
    /// Light groups plus lamps that are not part of any group (Hue rooms are never shown).
    var lights: [HAEntity] = []
    var heating: RoomHeating?
    var fan: RoomFan?
    var thermostats: [HAEntity] = []
    /// The room thermometer (preferred over the thermostat's own reading).
    var temperature: HAEntity?
    var humidity: HAEntity?
    /// Humidity, CO₂, air quality, particulate matter …
    var airSensors: [HAEntity] = []
    var batteries: [HAEntity] = []
    /// Switches, covers, fans and other toggles.
    var devices: [HAEntity] = []

    var isEmpty: Bool {
        lights.isEmpty && thermostats.isEmpty && airSensors.isEmpty && devices.isEmpty
            && temperature == nil && heating == nil && fan == nil
    }

    var lightsOn: [HAEntity] { lights.filter { $0.state == "on" } }

    var currentTemperature: Double? {
        temperature.flatMap { Double($0.state) } ?? thermostats.lazy.compactMap(\.currentTemperature).first
    }

    var isHeating: Bool { thermostats.contains { $0.hvacAction == "heating" } }
}

/// The heating helpers of one room, driven by the "Heizung: Externe Thermometer nutzen" automation.
struct RoomHeating {
    /// `input_number.wunschtemperatur_<area>`: what the room is really set to. Can be changed by hand at any time.
    let target: HAEntity
    /// `input_select.heizmodus_<area>` (Komfort / Nacht / Abwesend, plus "Manuell" after turning the dial by hand)
    let mode: HAEntity?
    /// `input_number.aufwarmtemperatur_<area>`: the fixed temperature for "Komfort".
    let warmup: HAEntity?
    /// `input_number.temperatur_nacht` / `input_number.temperatur_abwesend` in °C.
    var nightTemperature: Double?
    var awayTemperature: Double?
    /// `input_boolean.morgens_aufwarmen_<area>`: whether the room is warmed up in the morning.
    var wakeEnabled: HAEntity?
    /// `input_number.morgentemperatur_<area>`: how warm the room should be at the wake-up time.
    var wakeTemperature: HAEntity?
    /// `input_number.aufheizzeit_<area>`: minutes per degree, learned each morning by "Heizung: Aufheizzeit messen".
    var warmupRate: HAEntity?
    /// `counter.aufheizen_gelernt_<area>`: how many mornings were measured.
    var learnedMornings: HAEntity?

    var targetValue: Double? { Double(target.state) }
    var wakeTemperatureValue: Double? { wakeTemperature.flatMap { Double($0.state) } }
    var isWakeEnabled: Bool { wakeEnabled?.state == "on" }
    var minutesPerDegree: Double { warmupRate.flatMap { Double($0.state) } ?? 30 }
    var learnedCount: Int { learnedMornings.flatMap { Int($0.state) } ?? 0 }

    /// Minutes before the wake-up time the room starts heating, as computed by
    /// "Heizung: Vor dem Aufstehen aufwärmen": degrees to gain × learned minutes per degree, 15–240 min, 45 without a reading.
    func warmupLead(from current: Double?) -> Int {
        guard let current, let target = wakeTemperatureValue else { return 45 }
        return min(240, max(15, Int(((target - current) * minutesPerDegree).rounded())))
    }
    /// The modes one can choose. "Manuell" is left out: it is only set by turning the dial by hand
    /// (here or by "Heizung: Manuell erkennen" in HA).
    var modeOptions: [String] {
        (mode?.attributes["options"]?.array?.compactMap(\.string) ?? []).filter { $0 != Self.manualMode }
    }
    static let manualMode = "Manuell"

    /// The fixed temperature of a mode, as set in the settings.
    func preset(for mode: String) -> Double? {
        switch mode {
        case "Komfort": warmup.flatMap { Double($0.state) }
        case "Nacht": nightTemperature
        case "Abwesend": awayTemperature
        default: nil
        }
    }
}

/// The heater fans of a room, driven by the "Heizungslüfter <Raum>" automation: a plug powers them and
/// an ESP32 reads the speed from `input_number.heizungslufter_<area>_stufe` over the REST API.
struct RoomFan {
    /// Speed in % (0 = "Halten": plug on, fans at minimum).
    let speed: HAEntity
    /// The plug that powers the fans (`switch.<area>_luftung_heitzung_plug`).
    let power: HAEntity?
    /// `automation.heizungslufter_<area>`: sets speed and plug from the room's heat demand, lights and heating mode.
    let automation: HAEntity?
    /// `binary_sensor.<area>_braucht_warme`: room thermometer below the Wunschtemperatur.
    let demand: HAEntity?

    var speedValue: Double { Double(speed.state) ?? 0 }
    var speedRange: ClosedRange<Double> {
        (speed.attributes["min"]?.double ?? 0)...(speed.attributes["max"]?.double ?? 100)
    }
    var speedStep: Double { speed.attributes["step"]?.double ?? 5 }
    var isPowered: Bool { power.map { $0.state == "on" } ?? true }
    var isRunning: Bool { isPowered && speedValue > 0 }
    var isAutomatic: Bool { automation?.state == "on" }
    var needsHeat: Bool { demand?.state == "on" }

    var statusText: String {
        if power?.isUnavailable == true { return "Steckdose nicht erreichbar" }
        if !isPowered { return "Aus" }
        if speedValue <= 0 { return "Halten" }
        return "Läuft mit \(Int(speedValue.rounded())) %"
    }
}

/// House-wide heating helpers from the dashboard.
struct HeatingSettings {
    let nightTemperature: HAEntity?
    let awayTemperature: HAEntity?
    /// The time the rooms should be warm (`input_datetime.aufstehzeit`).
    let wakeTime: HAEntity?
    let morningWarmup: HAEntity?

    var entityIds: [String] {
        [nightTemperature, awayTemperature, wakeTime, morningWarmup].compactMap { $0?.entityId }
    }

    var wakeMinutes: Int? {
        guard let wakeTime, let hour = wakeTime.attributes["hour"]?.int,
              let minute = wakeTime.attributes["minute"]?.int else { return nil }
        return hour * 60 + minute
    }

    /// "07:00" for minutes after midnight, wrapping around the day.
    static func clock(_ minutes: Int) -> String {
        let wrapped = (minutes % (24 * 60) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}

extension HAEntity {
    var isGroupLight: Bool {
        domain == "light" && (attributes["entity_id"] != nil || attributes["is_hue_group"]?.bool == true)
    }

    var groupMembers: [String] {
        (attributes["entity_id"] ?? attributes["group_entities"])?.array?.compactMap(\.string) ?? []
    }

    /// The group Hue creates for a whole room (as opposed to a zone like "Setup").
    var isHueRoom: Bool { isGroupLight && attributes["hue_type"]?.string == "room" }

    var isBattery: Bool { domain == "sensor" && deviceClass == "battery" }
}

extension HomeStore {
    // MARK: Area resolution

    /// Area of every entity: registry first, then the area named in the entity's name,
    /// then (for light groups) the area most of its lamps are in.
    func resolveAreas() -> [String: String] {
        var result = entityAreas
        let areasByLength = areas.sorted { $0.name.count > $1.name.count }

        for entity in entities.values where result[entity.entityId] == nil {
            if let area = areasByLength.first(where: { entity.friendlyName.localizedCaseInsensitiveContains($0.name) }) {
                result[entity.entityId] = area.id
            }
        }

        let groups = entities.values.filter(\.isGroupLight)
        for group in groups where result[group.entityId] == nil {
            let memberAreas = group.groupMembers.compactMap { result[$0] }
            let counts = Dictionary(memberAreas.map { ($0, 1) }, uniquingKeysWith: +)
            if let majority = counts.max(by: { $0.value < $1.value })?.key {
                result[group.entityId] = majority
            }
        }

        return result
    }

    func areaName(for entityId: String) -> String? {
        guard let areaId = resolvedAreas[entityId] else { return nil }
        return areas.first { $0.id == areaId }?.name
    }

    // MARK: Heating

    var heatingSettings: HeatingSettings {
        HeatingSettings(
            nightTemperature: entities["input_number.temperatur_nacht"],
            awayTemperature: entities["input_number.temperatur_abwesend"],
            wakeTime: entities["input_datetime.aufstehzeit"],
            morningWarmup: entities["input_boolean.morgens_aufwarmen"]
        )
    }

    func roomHeating(areaId: String) -> RoomHeating? {
        let inArea = entities.values.filter { resolvedAreas[$0.entityId] == areaId }
        guard let target = entities["input_number.wunschtemperatur_\(areaId)"]
            ?? inArea.first(where: { $0.domain == "input_number" && $0.entityId.contains("wunsch") }) else { return nil }
        let mode = entities["input_select.heizmodus_\(areaId)"]
            ?? inArea.first(where: { $0.domain == "input_select" && $0.entityId.contains("modus") })
        let settings = heatingSettings
        return RoomHeating(
            target: target, mode: mode,
            warmup: entities["input_number.aufwarmtemperatur_\(areaId)"],
            nightTemperature: settings.nightTemperature.flatMap { Double($0.state) },
            awayTemperature: settings.awayTemperature.flatMap { Double($0.state) },
            wakeEnabled: entities["input_boolean.morgens_aufwarmen_\(areaId)"],
            wakeTemperature: entities["input_number.morgentemperatur_\(areaId)"],
            warmupRate: entities["input_number.aufheizzeit_\(areaId)"],
            learnedMornings: entities["counter.aufheizen_gelernt_\(areaId)"]
        )
    }

    /// The heater fans of a room, if it has a speed helper.
    func roomFan(areaId: String) -> RoomFan? {
        guard let speed = entities["input_number.heizungslufter_\(areaId)_stufe"] else { return nil }
        // The plug has no area in HA and a generic name, so look it up by its entity id.
        let power = entities["switch.\(areaId)_luftung_heitzung_plug"]
            ?? entities.values.first { $0.domain == "switch" && $0.entityId.hasPrefix("switch.\(areaId)_") && $0.entityId.contains("luft") }
        return RoomFan(
            speed: speed, power: power,
            automation: entities["automation.heizungslufter_\(areaId)"],
            demand: entities["binary_sensor.\(areaId)_braucht_warme"]
        )
    }

    /// Heating helpers for the room a thermostat belongs to.
    func roomHeating(forThermostat entityId: String) -> RoomHeating? {
        resolvedAreas[entityId].flatMap(roomHeating(areaId:))
    }

    /// How far a thermostat's valve is open in percent: from its own attributes or a "valve"/"pi_heating_demand"
    /// sensor of the same device (Zigbee2MQTT, deCONZ, Tado …).
    func valvePosition(of thermostat: HAEntity) -> Double? {
        for key in ["valve_position", "pi_heating_demand", "heating_demand"] {
            if let value = thermostat.attributes[key]?.double { return value }
        }
        guard let device = entityDevices[thermostat.entityId] else { return nil }
        return entities.values.first { entity in
            entity.entityId != thermostat.entityId && entityDevices[entity.entityId] == device
                && ["sensor", "number"].contains(entity.domain)
                && entity.attributes["unit_of_measurement"]?.string == "%"
                && ["valve", "pi_heating_demand", "heating_demand"].contains { entity.entityId.contains($0) }
        }.flatMap { Double($0.state) }
    }

    /// All room modes, for "Alle Nacht" etc.
    var heatingModes: [HAEntity] { rooms.compactMap { $0.heating?.mode } }

    /// Switches the room to a mode and sets it to that mode's fixed temperature,
    /// also when it is already in that mode but was changed by hand.
    func selectHeatingMode(_ heating: RoomHeating, _ option: String) {
        if let mode = heating.mode, mode.state != option { selectOption(mode, option) }
        if let preset = heating.preset(for: option), preset != heating.targetValue { setValue(heating.target, to: preset) }
    }

    /// Sets the Wunschtemperatur by hand. The room then shows "Manuell" (unless the value is the fixed one of
    /// its mode), so the morning warm-up still picks it up. HA's "Heizung: Manuell erkennen" does the same.
    func setTargetByHand(_ heating: RoomHeating, to value: Double) {
        setValue(heating.target, to: value)
        guard let mode = heating.mode, mode.state != RoomHeating.manualMode,
              mode.attributes["options"]?.array?.contains(where: { $0.string == RoomHeating.manualMode }) == true,
              heating.preset(for: mode.state).map({ abs($0 - value) >= 0.05 }) ?? true else { return }
        selectOption(mode, RoomHeating.manualMode)
    }

    func setAllHeatingModes(_ option: String) {
        Haptics.tap()
        for heating in rooms.compactMap(\.heating) { selectHeatingMode(heating, option) }
    }

    // MARK: Rooms

    private func isVisible(_ entity: HAEntity) -> Bool {
        guard entity.kind != .unsupported, !hiddenEntities.contains(entity.entityId) else { return false }
        return !categorizedEntities.contains(entity.entityId) || entity.isBattery
    }

    var rooms: [Room] {
        let visible = entities.values.filter(isVisible)
        let groups = visible.filter(\.isGroupLight)
        // Hue rooms are never shown. Their lamps are hidden if the room has its own light groups (Wohnzimmer),
        // otherwise they are shown one by one (Schlafzimmer).
        let redundantHueRooms = Set(groups.filter { hueRoom in
            hueRoom.isHueRoom && groups.contains {
                !$0.isHueRoom && resolvedAreas[$0.entityId] == resolvedAreas[hueRoom.entityId]
            }
        }.map(\.entityId))
        let groupedLamps = Set(groups.filter { !$0.isHueRoom || redundantHueRooms.contains($0.entityId) }.flatMap(\.groupMembers))
        let thermostatDevices = Set(visible.filter { $0.kind == .climate }.compactMap { entityDevices[$0.entityId] })
        var consumed = Set(heatingSettings.entityIds)

        var byArea = Dictionary(uniqueKeysWithValues: areas.map {
            ($0.id, Room(id: $0.id, name: $0.name, symbol: Self.symbol(for: $0)))
        })
        for area in areas {
            if let heating = roomHeating(areaId: area.id) {
                byArea[area.id]?.heating = heating
                consumed.insert(heating.target.entityId)
                for helper in [heating.mode, heating.wakeEnabled, heating.wakeTemperature].compactMap({ $0 }) {
                    consumed.insert(helper.entityId)
                }
            }
            if let fan = roomFan(areaId: area.id) {
                byArea[area.id]?.fan = fan
                // The plug is controlled in the fan card, not as a separate device tile.
                for entity in [fan.speed, fan.power, fan.demand].compactMap({ $0 }) { consumed.insert(entity.entityId) }
            }
        }

        var other = Room(id: "", name: "Weitere", symbol: "square.grid.2x2")

        for entity in visible where !consumed.contains(entity.entityId) {
            if entity.kind == .light, groupedLamps.contains(entity.entityId) || entity.isHueRoom { continue }
            guard let areaId = resolvedAreas[entity.entityId], byArea[areaId] != nil else {
                // Without a room only controllable things are worth showing (no sun or backup sensors).
                switch entity.kind {
                case .light: other.lights.append(entity)
                case .toggle, .cover, .climate: other.devices.append(entity)
                default: break
                }
                continue
            }
            switch entity.kind {
            case .light:
                byArea[areaId]!.lights.append(entity)
            case .climate:
                byArea[areaId]!.thermostats.append(entity)
            case .scene:
                // Scenes come from Apple Home (AppleHomeScenes); scripts are HA internals.
                continue
            case .sensor:
                if entity.isBattery {
                    byArea[areaId]!.batteries.append(entity)
                } else if let device = entityDevices[entity.entityId], thermostatDevices.contains(device) {
                    // Thermostat extras such as "HLK-Aktion" are already shown in the heating card.
                    continue
                } else if entity.deviceClass == "temperature", byArea[areaId]!.temperature == nil {
                    byArea[areaId]!.temperature = entity
                } else if entity.deviceClass != "temperature", entity.domain == "sensor", entity.sensorLabel != nil {
                    // Only real room readings, like on the dashboard (no Hue entertainment areas or other status flags).
                    if entity.deviceClass == "humidity", byArea[areaId]!.humidity == nil {
                        byArea[areaId]!.humidity = entity
                    }
                    byArea[areaId]!.airSensors.append(entity)
                }
            default:
                byArea[areaId]!.devices.append(entity)
            }
        }

        var result = areas.compactMap { byArea[$0.id] }
        result.append(other)
        return ordered(result.filter { !$0.isEmpty }.map(Self.sorted))
    }

    /// Applies the user's room order; new rooms keep their HA position after the sorted ones.
    private func ordered(_ rooms: [Room]) -> [Room] {
        let position = Dictionary(roomOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return rooms.enumerated()
            .sorted { lhs, rhs in
                let left = position[lhs.element.id] ?? roomOrder.count + lhs.offset
                let right = position[rhs.element.id] ?? roomOrder.count + rhs.offset
                return left < right
            }
            .map(\.element)
    }

    private static func sorted(_ room: Room) -> Room {
        var room = room
        let byName: (HAEntity, HAEntity) -> Bool = {
            $0.friendlyName.localizedStandardCompare($1.friendlyName) == .orderedAscending
        }
        room.lights.sort { lhs, rhs in
            let left = (lhs.isUnavailable ? 1 : 0, lhs.isGroupLight ? 0 : 1)
            let right = (rhs.isUnavailable ? 1 : 0, rhs.isGroupLight ? 0 : 1)
            return left != right ? left < right : byName(lhs, rhs)
        }
        room.thermostats.sort(by: byName)
        room.devices.sort(by: byName)
        room.batteries.sort(by: byName)
        let sensorOrder = ["humidity", "carbon_dioxide", "aqi", "pm25", "pm10"]
        room.airSensors.sort { lhs, rhs in
            let left = sensorOrder.firstIndex(of: lhs.sensorKind) ?? sensorOrder.count
            let right = sensorOrder.firstIndex(of: rhs.sensorKind) ?? sensorOrder.count
            return left != right ? left < right : byName(lhs, rhs)
        }
        return room
    }

    // MARK: Names

    /// Tile name inside a room. A group named like the room is "Alle Lampen" if it really contains all of them.
    func displayName(for entity: HAEntity, inRoom room: String?) -> String {
        if entity.isGroupLight, let room, entity.friendlyName.caseInsensitiveCompare(room) == .orderedSame {
            let areaId = resolvedAreas[entity.entityId]
            let lampsInRoom = entities.values.filter { $0.domain == "light" && !$0.isGroupLight && resolvedAreas[$0.entityId] == areaId }
            let members = Set(entity.groupMembers)
            return lampsInRoom.allSatisfy { members.contains($0.entityId) } ? "Alle Lampen" : "Hue-Raum"
        }
        if entity.domain == "sensor", let label = entity.sensorLabel { return label }
        return entity.displayName(inRoom: room)
    }

    /// Maps the area's mdi icon (or its name) to an SF Symbol.
    static func symbol(for area: HAArea) -> String {
        let icons: [String: String] = [
            "mdi:sofa": "sofa.fill", "mdi:sofa-outline": "sofa.fill", "mdi:television": "tv.fill",
            "mdi:stove": "oven.fill", "mdi:silverware-fork-knife": "fork.knife", "mdi:fridge": "refrigerator.fill",
            "mdi:bed": "bed.double.fill", "mdi:bed-king": "bed.double.fill", "mdi:bed-outline": "bed.double.fill",
            "mdi:shower": "shower.fill", "mdi:bathtub": "bathtub.fill", "mdi:toilet": "toilet.fill",
            "mdi:desk": "desktopcomputer", "mdi:garage": "door.garage.closed", "mdi:tree": "tree.fill",
            "mdi:flower": "leaf.fill", "mdi:washing-machine": "washer.fill", "mdi:door": "door.left.hand.closed",
        ]
        if let icon = area.icon, let symbol = icons[icon] { return symbol }
        let name = area.name.lowercased()
        let byName: [(String, String)] = [
            ("wohn", "sofa.fill"), ("küche", "oven.fill"), ("kuche", "oven.fill"), ("schlaf", "bed.double.fill"),
            ("bad", "shower.fill"), ("flur", "door.left.hand.open"), ("diele", "door.left.hand.open"),
            ("büro", "desktopcomputer"), ("arbeit", "desktopcomputer"), ("kind", "teddybear.fill"),
            ("garten", "tree.fill"), ("balkon", "sun.max.fill"), ("terrasse", "sun.max.fill"),
            ("keller", "archivebox.fill"), ("garage", "door.garage.closed"), ("ess", "fork.knife"),
        ]
        return byName.first { name.contains($0.0) }?.1 ?? "square.split.bottomrightquarter"
    }
}

extension HAEntity {
    /// Normalised sensor type, also for sensors without device class (e.g. "Luftqualität").
    var sensorKind: String {
        // The air quality rating ("good") comes as an enum sensor, so check it before the device class.
        if entityId.contains("air_quality") && !isUnavailable && Double(state) == nil { return "aqi" }
        if let deviceClass { return deviceClass }
        return ""
    }

    /// Short German label for room sensors, as on the dashboard.
    var sensorLabel: String? {
        switch sensorKind {
        case "temperature": "Temperatur"
        case "humidity": "Luftfeuchte"
        case "carbon_dioxide": "CO₂"
        case "aqi": "Luftqualität"
        case "pm25": "Feinstaub PM2,5"
        case "pm10": "Feinstaub PM10"
        case "illuminance": "Helligkeit"
        default: nil
        }
    }

    /// Traffic-light rating for air sensors: 0 = good, 1 = moderate, 2 = poor.
    var airRating: Int? {
        let value = Double(state)
        switch sensorKind {
        case "carbon_dioxide": return value.map { $0 < 800 ? 0 : $0 < 1200 ? 1 : 2 }
        case "humidity": return value.map { (40...60).contains($0) ? 0 : (30...65).contains($0) ? 1 : 2 }
        case "pm25": return value.map { $0 < 10 ? 0 : $0 < 25 ? 1 : 2 }
        case "aqi":
            switch state {
            case "excellent", "good": return 0
            case "moderate", "fair": return 1
            case "poor", "unhealthy", "very_poor": return 2
            default: return nil
            }
        default: return nil
        }
    }
}
