import Foundation

/// A Home Assistant service call targeting a single entity.
struct ServiceCall: Sendable, Hashable {
    let domain: String
    let service: String
    let entityId: String
    var data: [String: JSONValue] = [:]

    /// Payload for the WebSocket `call_service` command (without `id`/`type`).
    var websocketPayload: [String: JSONValue] {
        [
            "domain": .string(domain),
            "service": .string(service),
            "service_data": .object(data),
            "target": ["entity_id": .string(entityId)],
        ]
    }

    /// Request body for `POST /api/services/<domain>/<service>`.
    var restBody: [String: JSONValue] {
        var body = data
        body["entity_id"] = .string(entityId)
        return body
    }
}

extension ServiceCall {
    private static func domain(of entityId: String) -> String {
        String(entityId.prefix { $0 != "." })
    }

    /// Tap action that does not need the current state (used by the widget and Siri).
    static func toggle(entityId: String) -> ServiceCall {
        let domain = domain(of: entityId)
        switch DeviceKind(domain: domain) {
        case .scene: return ServiceCall(domain: domain, service: "turn_on", entityId: entityId)
        default: return ServiceCall(domain: domain, service: "toggle", entityId: entityId)
        }
    }

    /// Explicit on/off. Covers open/close, scenes and scripts are always activated.
    static func power(entityId: String, on: Bool) -> ServiceCall {
        let domain = domain(of: entityId)
        switch DeviceKind(domain: domain) {
        case .cover:
            return ServiceCall(domain: domain, service: on ? "open_cover" : "close_cover", entityId: entityId)
        case .scene:
            return ServiceCall(domain: domain, service: "turn_on", entityId: entityId)
        default:
            return ServiceCall(domain: domain, service: on ? "turn_on" : "turn_off", entityId: entityId)
        }
    }
}

extension HAEntity {
    /// The service call for a tap on the tile, plus the state we expect afterwards (for optimistic UI).
    func tapAction() -> (call: ServiceCall, predicted: HAEntity?)? {
        guard !isUnavailable else { return nil }
        var predicted = self
        switch kind {
        case .light, .toggle:
            let turnOn = state != "on"
            predicted.state = turnOn ? "on" : "off"
            return (.power(entityId: entityId, on: turnOn), predicted)
        case .climate:
            let turnOn = state == "off"
            predicted.state = turnOn ? (hvacModes.first { $0 != "off" } ?? "heat") : "off"
            return (.power(entityId: entityId, on: turnOn), predicted)
        case .cover:
            let open = state == "closed" || state == "closing"
            predicted.state = open ? "opening" : "closing"
            return (.power(entityId: entityId, on: open), predicted)
        case .scene:
            return (.power(entityId: entityId, on: true), nil)
        case .sensor, .unsupported:
            return nil
        }
    }
}
