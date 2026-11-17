import AppIntents
import WidgetKit

enum WidgetKinds {
    static let favorites = "FavoritesWidget"
}

/// A switchable Home Assistant entity as seen by Siri, Shortcuts and the widget.
struct DeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gerät"
    static let defaultQuery = DeviceQuery()

    let id: String
    let name: String
    let room: String?

    init(id: String, name: String, room: String?) {
        self.id = id
        self.name = name
        self.room = room
    }

    init(_ device: CachedDevice) {
        self.init(id: device.id, name: device.name, room: device.areaName)
    }

    var displayRepresentation: DisplayRepresentation {
        if let room {
            DisplayRepresentation(title: "\(name)", subtitle: "\(room)")
        } else {
            DisplayRepresentation(title: "\(name)")
        }
    }
}

struct DeviceQuery: EntityStringQuery {
    /// Devices from the cache written by the app; loads them directly from HA if the cache is empty.
    private func allDevices() async throws -> [DeviceEntity] {
        var devices = SharedStorage.cachedDevices
        if devices.isEmpty {
            let states = try await HARestClient.resolve().states()
            devices = states.map { CachedDevice(entity: $0, areaName: nil) }
        }
        return devices
            .filter { $0.entity.kind.isControllable }
            .map(DeviceEntity.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func entities(for identifiers: [DeviceEntity.ID]) async throws -> [DeviceEntity] {
        let devices = try await allDevices()
        return identifiers.compactMap { id in devices.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [DeviceEntity] {
        let needle = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return try await allDevices().filter { device in
            let haystack = ([device.name, device.room ?? ""]).joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(needle)
        }
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        try await allDevices()
    }
}

/// Runs a service call over REST and refreshes the widget.
enum DeviceActions {
    static func perform(_ call: ServiceCall) async throws {
        let changed = try await HARestClient.resolve().call(call)
        SharedStorage.updateCache(with: changed)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.favorites)
    }
}

struct ToggleDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Gerät umschalten"
    static let description = IntentDescription("Schaltet ein Gerät in Home Assistant um.")

    @Parameter(title: "Gerät")
    var device: DeviceEntity

    init() {}

    init(device: DeviceEntity) {
        self.device = device
    }

    func perform() async throws -> some IntentResult {
        try await DeviceActions.perform(.toggle(entityId: device.id))
        return .result()
    }
}

struct TurnOnDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Gerät einschalten"
    static let description = IntentDescription("Schaltet ein Gerät in Home Assistant ein.")

    @Parameter(title: "Gerät")
    var device: DeviceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Schalte \(\.$device) ein")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await DeviceActions.perform(.power(entityId: device.id, on: true))
        return .result(dialog: "\(device.name) ist an.")
    }
}

struct TurnOffDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Gerät ausschalten"
    static let description = IntentDescription("Schaltet ein Gerät in Home Assistant aus.")

    @Parameter(title: "Gerät")
    var device: DeviceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Schalte \(\.$device) aus")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await DeviceActions.perform(.power(entityId: device.id, on: false))
        return .result(dialog: "\(device.name) ist aus.")
    }
}
