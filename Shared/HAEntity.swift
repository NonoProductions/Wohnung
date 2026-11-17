import Foundation

/// A Home Assistant entity state as delivered by `get_states`, `state_changed` and `/api/states`.
struct HAEntity: Sendable, Hashable, Identifiable, Codable {
    let entityId: String
    var state: String
    var attributes: [String: JSONValue]
    var lastChanged: String?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
    }

    var id: String { entityId }
    var domain: String { String(entityId.prefix { $0 != "." }) }
    var kind: DeviceKind { DeviceKind(domain: domain) }
    var friendlyName: String { attributes["friendly_name"]?.string ?? entityId }
    var deviceClass: String? { attributes["device_class"]?.string }
    var isUnavailable: Bool { state == "unavailable" }

    /// Name without the room word, e.g. "Wohnzimmer Lesen" → "Lesen",
    /// "Deckenlampe Wohnzimmer" → "Deckenlampe" and "Heizung Bad 2" → "Heizung 2".
    func displayName(inRoom room: String?) -> String {
        let name = friendlyName
        guard let room, !room.isEmpty else { return name }
        let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: room) + "(?![\\p{L}\\p{N}])"
        let stripped = name
            .replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
        return stripped.isEmpty ? name : stripped
    }

    /// Whether the tile should be rendered in its "on" style.
    var isActive: Bool {
        switch kind {
        case .light, .toggle: return state == "on"
        case .climate: return state != "off" && !isUnavailable
        case .cover: return ["open", "opening", "closing"].contains(state)
        case .sensor: return domain == "binary_sensor" && state == "on"
        case .scene, .unsupported: return false
        }
    }

    // MARK: Light

    /// Brightness in percent (0...100), nil if the light is off or not dimmable.
    var brightnessPercent: Int? {
        guard state == "on", let raw = attributes["brightness"]?.double else { return nil }
        return Int((raw / 255 * 100).rounded())
    }

    var supportedColorModes: [String] {
        attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? []
    }

    var isDimmable: Bool { supportedColorModes.contains { $0 != "onoff" } }
    var supportsColorTemperature: Bool { supportedColorModes.contains("color_temp") }
    var supportsColor: Bool {
        supportedColorModes.contains { ["hs", "xy", "rgb", "rgbw", "rgbww"].contains($0) }
    }

    /// The light's current colour as RGB (0...1), if reported.
    var rgbColor: (red: Double, green: Double, blue: Double)? {
        guard let values = attributes["rgb_color"]?.array?.compactMap(\.double), values.count == 3 else { return nil }
        return (values[0] / 255, values[1] / 255, values[2] / 255)
    }

    // MARK: Climate

    var currentTemperature: Double? { attributes["current_temperature"]?.double }
    var targetTemperature: Double? { attributes["temperature"]?.double }
    var hvacAction: String? { attributes["hvac_action"]?.string }
    var hvacModes: [String] { attributes["hvac_modes"]?.array?.compactMap(\.string) ?? [] }
    var minTemperature: Double { attributes["min_temp"]?.double ?? 7 }
    var maxTemperature: Double { attributes["max_temp"]?.double ?? 30 }
    var temperatureStep: Double { attributes["target_temp_step"]?.double ?? 0.5 }

    // MARK: Cover

    var coverPosition: Int? { attributes["current_position"]?.int }
}

/// The kinds of devices the app knows how to show and control.
enum DeviceKind: String, Sendable, Codable {
    case light, climate, cover, toggle, scene, sensor, unsupported

    init(domain: String) {
        switch domain {
        case "light": self = .light
        case "climate": self = .climate
        case "cover": self = .cover
        case "switch", "input_boolean", "fan": self = .toggle
        case "scene", "script": self = .scene
        case "sensor", "binary_sensor": self = .sensor
        default: self = .unsupported
        }
    }

    /// Kinds that can be switched with a single tap (and therefore by Siri and the widget).
    var isControllable: Bool { ![.sensor, .unsupported].contains(self) }

    /// Sort order inside a room.
    var sortOrder: Int {
        switch self {
        case .light: 0
        case .climate: 1
        case .cover: 2
        case .toggle: 3
        case .scene: 4
        case .sensor: 5
        case .unsupported: 6
        }
    }
}
