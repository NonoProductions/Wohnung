import Foundation

/// German status texts and SF Symbols for entities, shared by the app and the widget.
extension HAEntity {
    var symbolName: String {
        switch domain {
        case "light":
            return attributes["entity_id"] != nil || attributes["is_hue_group"] != nil ? "lightbulb.2" : "lightbulb"
        case "switch", "input_boolean": return "power"
        case "fan": return "fan"
        case "climate": return "heater.vertical"
        case "cover":
            switch deviceClass {
            case "garage": return state == "closed" ? "door.garage.closed" : "door.garage.open"
            case "door", "gate": return state == "closed" ? "door.left.hand.closed" : "door.left.hand.open"
            default: return state == "closed" ? "blinds.vertical.closed" : "blinds.vertical.open"
            }
        case "scene": return "sparkles"
        case "script": return "play"
        case "binary_sensor":
            switch deviceClass {
            case "door", "garage_door", "opening": return state == "on" ? "door.left.hand.open" : "door.left.hand.closed"
            case "window": return state == "on" ? "window.vertical.open" : "window.vertical.closed"
            case "motion", "occupancy", "presence": return "figure.walk"
            case "moisture": return "drop"
            case "smoke": return "smoke"
            default: return "circle.dashed"
            }
        case "sensor":
            switch deviceClass {
            case "temperature": return "thermometer.medium"
            case "humidity": return "humidity"
            case "carbon_dioxide": return "carbon.dioxide.cloud"
            case "pm25", "pm10", "aqi", "volatile_organic_compounds": return "aqi.medium"
            case "battery": return "battery.75percent"
            case "illuminance": return "sun.max"
            case "power", "energy", "current", "voltage": return "bolt"
            default:
                if entityId.contains("air_quality") { return "aqi.medium" }
                return "gauge.with.dots.needle.50percent"
            }
        default: return "questionmark.circle"
        }
    }

    var statusText: String {
        if isUnavailable { return "Nicht erreichbar" }
        switch kind {
        case .light:
            guard state == "on" else { return "Aus" }
            return brightnessPercent.map { "An · \($0) %" } ?? "An"
        case .toggle:
            return state == "on" ? "An" : "Aus"
        case .climate:
            guard state != "off" else { return "Aus" }
            var parts: [String] = []
            if let current = currentTemperature { parts.append(Self.formatTemperature(current)) }
            if let target = targetTemperature { parts.append("Ziel \(Self.formatTemperature(target))") }
            return parts.isEmpty ? Self.hvacModeName(state) : parts.joined(separator: " · ")
        case .cover:
            switch state {
            case "open":
                if let position = coverPosition, position < 100 { return "Offen · \(position) %" }
                return "Offen"
            case "closed": return "Geschlossen"
            case "opening": return "Öffnet …"
            case "closing": return "Schließt …"
            default: return state
            }
        case .scene:
            return domain == "script" ? "Skript" : "Szene"
        case .sensor:
            return sensorValueText
        case .unsupported:
            return state
        }
    }

    /// Formatted sensor value including the unit.
    var sensorValueText: String {
        if isUnavailable { return "Nicht erreichbar" }
        if state == "unknown" { return "–" }
        if domain == "binary_sensor" {
            let on = state == "on"
            switch deviceClass {
            case "door", "garage_door", "opening", "window": return on ? "Offen" : "Geschlossen"
            case "motion", "occupancy", "presence": return on ? "Erkannt" : "Frei"
            case "moisture": return on ? "Nass" : "Trocken"
            default: return on ? "An" : "Aus"
            }
        }
        if let number = Double(state) {
            let unit = attributes["unit_of_measurement"]?.string
            let value = number.formatted(.number.precision(.fractionLength(0...1)))
            guard let unit, !unit.isEmpty else { return value }
            return unit == "%" ? "\(value) %" : "\(value) \(unit)"
        }
        return Self.translatedState(state)
    }

    /// German name of a text state such as "good" or "moderate".
    static func translatedState(_ state: String) -> String {
        stateTranslations[state] ?? state
    }

    static func formatTemperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    static func hvacModeName(_ mode: String) -> String {
        switch mode {
        case "off": "Aus"
        case "heat": "Heizen"
        case "cool": "Kühlen"
        case "auto": "Auto"
        case "heat_cool": "Heizen/Kühlen"
        case "dry": "Entfeuchten"
        case "fan_only": "Lüften"
        default: mode
        }
    }

    private static let stateTranslations: [String: String] = [
        "excellent": "Ausgezeichnet",
        "good": "Gut",
        "moderate": "Mäßig",
        "fair": "Mäßig",
        "poor": "Schlecht",
        "unhealthy": "Ungesund",
        "heating": "Heizt",
        "cooling": "Kühlt",
        "idle": "Leerlauf",
        "off": "Aus",
        "on": "An",
    ]
}
