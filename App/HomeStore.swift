import AppIntents
import Foundation
import Network
import Observation
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class HomeStore {
    enum ConnectionStatus: Equatable {
        case idle
        case connecting
        case connected(URL)
        case waiting(retryAt: Date)
        case failed(String)
    }

    private(set) var status: ConnectionStatus = .idle
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var areas: [HAArea] = []
    private(set) var favorites: [String] = SharedStorage.favorites
    /// Room ids in the order chosen by the user; rooms not listed follow in HA order.
    private(set) var roomOrder: [String] = SharedStorage.roomOrder
    private(set) var configuration: ServerConfiguration? = SharedStorage.serverConfiguration
    private(set) var hasToken = TokenStore.load() != nil
    /// Short-lived error shown as a banner (e.g. a rejected command).
    private(set) var transientError: String?
    /// True once a connection problem has lasted longer than `connectionBannerDelay`.
    /// Short drops (app reopened, Wi-Fi hiccup) reconnect silently without a banner.
    private(set) var isConnectionProblemVisible = false
    /// Scenes that were just activated, for a short highlight.
    private(set) var recentlyActivated: Set<String> = []
    /// The entity whose detail sheet is shown.
    var presentedDetail: DetailItem?
    /// Settings sheet and the room navigation path on the overview.
    var isShowingSettings = false
    var roomPath: [String] = []

    /// Registry data used to build rooms (see RoomModel.swift).
    private(set) var entityAreas: [String: String] = [:]
    private(set) var entityDevices: [String: String] = [:]
    /// Entities hidden or disabled in HA.
    private(set) var hiddenEntities: Set<String> = []
    /// Area of each entity after applying the fallbacks in `resolveAreas()`.
    private(set) var resolvedAreas: [String: String] = [:]
    /// Config/diagnostic entities (firmware, transition times, batteries …).
    private(set) var categorizedEntities: Set<String> = []

    @ObservationIgnored private let client = HAWebSocketClient()
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var pending: [String: PendingChange] = [:]
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private var connectionBannerTask: Task<Void, Never>?
    /// How long a connection problem must last before a banner appears.
    private static let connectionBannerDelay: Duration = .seconds(15)
    @ObservationIgnored private var favoritesChanged = false
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var isOnLocalNetwork: Bool?
    @ObservationIgnored private var isActive = false

    private struct PendingChange {
        let original: HAEntity
        let timeout: Task<Void, Never>
    }

    var isConfigured: Bool { (configuration?.isComplete ?? false) && hasToken }

    init() {
        client.onEvent = { [weak self] event in self?.handle(event: event) }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let local = ServerResolver.isLocal(path)
            Task { @MainActor in self?.networkChanged(isLocal: local) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Zuhause.PathMonitor"))
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            if connectionTask == nil {
                start()
            } else if case .waiting = status {
                restart()
            }
        case .background:
            isActive = false
            stop()
        default:
            break
        }
    }

    func start() {
        guard connectionTask == nil, isConfigured else { return }
        connectionTask = Task { await connectionLoop() }
    }

    func stop() {
        connectionTask?.cancel()
        connectionTask = nil
        client.disconnect()
        status = .idle
        hideConnectionBanner()
    }

    func restart() {
        stop()
        failedAttempts = 0
        start()
    }

    private func networkChanged(isLocal: Bool) {
        defer { isOnLocalNetwork = isLocal }
        // Switching between Wi-Fi and cellular means a different URL – reconnect right away.
        guard let previous = isOnLocalNetwork, previous != isLocal, isActive, isConfigured else { return }
        restart()
    }

    // MARK: Setup

    func configure(_ configuration: ServerConfiguration, token: String?) throws {
        if let token {
            try TokenStore.save(token)
            hasToken = true
        }
        SharedStorage.serverConfiguration = configuration
        self.configuration = configuration
        restart()
    }

    func signOut() {
        stop()
        TokenStore.delete()
        SharedStorage.serverConfiguration = nil
        SharedStorage.cachedDevices = []
        hasToken = false
        configuration = nil
        entities = [:]
        areas = []
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Connection

    private func connectionLoop() async {
        while !Task.isCancelled {
            guard let configuration, let token = TokenStore.load() else { return }
            status = .connecting
            scheduleConnectionBanner()
            do {
                try await runConnection(configuration: configuration, token: token)
            } catch HAError.unauthorized {
                status = .failed(HAError.unauthorized.localizedDescription)
                connectionTask = nil
                return
            } catch {}
            guard !Task.isCancelled else { return }

            // Exponential backoff: 1, 2, 4, 8, 16, 32, then every 60 seconds.
            failedAttempts += 1
            let delay = min(60, pow(2, Double(failedAttempts - 1)))
            status = .waiting(retryAt: .now.addingTimeInterval(delay))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func runConnection(configuration: ServerConfiguration, token: String) async throws {
        var connectedURL: URL?
        var lastError: Error = HAError.notReachable
        for url in await ServerResolver.candidates(for: configuration) {
            do {
                let timeout = ServerResolver.timeout(for: url, configuration: configuration)
                try await client.connect(to: url, token: token, timeout: timeout)
                connectedURL = url
                break
            } catch HAError.unauthorized {
                throw HAError.unauthorized
            } catch {
                lastError = error
            }
        }
        guard let connectedURL else { throw lastError }

        let client = self.client
        let connectionID = client.connectionID
        let receiveTask = Task { try await client.runReceiveLoop() }
        let sessionTask = Task {
            do {
                try await loadEverything()
                status = .connected(connectedURL)
                failedAttempts = 0
                hideConnectionBanner()
                try await keepAlive(connectionID: connectionID)
            } catch {
                // Loading failed or a ping timed out: close the socket so the receive loop ends.
                client.disconnect(connectionID: connectionID)
            }
        }
        defer { sessionTask.cancel() }
        // Returns once the socket is closed (by the server, the network or `stop()`).
        _ = await receiveTask.result
        throw HAError.disconnected
    }

    /// Subscribes to state changes and loads registries and states.
    private func loadEverything() async throws {
        try await client.send("subscribe_events", ["event_type": "state_changed"])

        // Registries need an admin token; without them the app still works, just without rooms.
        let areaList = try? await client.send("config/area_registry/list").decode([AreaEntry].self)
        let deviceList = try? await client.send("config/device_registry/list").decode([DeviceEntry].self)
        let entityList = try? await client.send("config/entity_registry/list").decode([EntityEntry].self)
        let states = try await client.send("get_states").decode([HAEntity].self)

        let deviceAreas = Dictionary(
            (deviceList ?? []).compactMap { device in device.areaId.map { (device.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var entityAreas: [String: String] = [:]
        var entityDevices: [String: String] = [:]
        var hidden: Set<String> = []
        var categorized: Set<String> = []
        for entry in entityList ?? [] {
            if entry.hiddenBy != nil || entry.disabledBy != nil { hidden.insert(entry.entityId) }
            if entry.entityCategory != nil { categorized.insert(entry.entityId) }
            if let device = entry.deviceId { entityDevices[entry.entityId] = device }
            if let area = entry.areaId ?? entry.deviceId.flatMap({ deviceAreas[$0] }) {
                entityAreas[entry.entityId] = area
            }
        }

        areas = (areaList ?? []).map { HAArea(id: $0.areaId, name: $0.name, icon: $0.icon) }
        self.entityAreas = entityAreas
        self.entityDevices = entityDevices
        hiddenEntities = hidden
        categorizedEntities = categorized
        for change in pending.values { change.timeout.cancel() }
        pending.removeAll()
        // Scenes come from Apple Home (AppleHomeScenes), Home Assistant's own scenes are left out everywhere.
        entities = Dictionary(
            states.filter { !Self.isExcluded($0.entityId) }.map { ($0.entityId, $0) },
            uniquingKeysWith: { _, last in last }
        )
        if favorites.contains(where: Self.isExcluded) {
            favorites.removeAll(where: Self.isExcluded)
            saveFavorites()
        }
        for group in entities.values where group.isGroupLight { correctGroupState(group.entityId) }
        resolvedAreas = resolveAreas()

        persistNow()
        ZuhauseShortcuts.updateAppShortcutParameters()
    }

    /// Home Assistant scenes, replaced by the scenes from Apple Home.
    private static func isExcluded(_ entityId: String) -> Bool { entityId.hasPrefix("scene.") }

    private func keepAlive(connectionID: Int) async throws {
        while true {
            try await Task.sleep(for: .seconds(25))
            let client = self.client
            let watchdog = Task {
                try await Task.sleep(for: .seconds(20))
                client.disconnect(connectionID: connectionID)
            }
            defer { watchdog.cancel() }
            try await client.send("ping")
        }
    }

    private func handle(event: JSONValue) {
        guard event["event_type"]?.string == "state_changed",
              let data = event["data"], let entityId = data["entity_id"]?.string,
              !Self.isExcluded(entityId) else { return }

        if let newState = data["new_state"], !newState.isNull,
           let entity = try? newState.decode(HAEntity.self) {
            pending.removeValue(forKey: entityId)?.timeout.cancel()
            let isNew = entities[entityId] == nil
            entities[entityId] = entity
            if isNew { resolvedAreas = resolveAreas() }
            reconcileGroups(after: entity)
        } else {
            entities[entityId] = nil
        }
        if favorites.contains(entityId) { favoritesChanged = true }
        schedulePersist()
    }

    // MARK: Light groups

    /// Hue sometimes keeps reporting a group (zone like "Setup") as on after its lamps were switched off
    /// elsewhere, e.g. in Apple Home. The lamps themselves report correctly, so the group follows them:
    /// on as soon as one lamp is on, off when all reachable lamps are off.
    private func reconcileGroups(after entity: HAEntity) {
        guard entity.domain == "light" else { return }
        if entity.isGroupLight {
            // The group's own update may arrive before its lamps'; check again once they had time to report.
            let groupId = entity.entityId
            Task {
                try? await Task.sleep(for: .seconds(3))
                correctGroupState(groupId)
            }
        } else {
            for group in entities.values where group.isGroupLight && group.groupMembers.contains(entity.entityId) {
                correctGroupState(group.entityId)
            }
        }
    }

    private func correctGroupState(_ groupId: String) {
        // Leave groups alone while a command of ours is still waiting for confirmation.
        guard pending[groupId] == nil, var group = entities[groupId], !group.isUnavailable else { return }
        let lamps = group.groupMembers.compactMap { entities[$0] }.filter { !$0.isUnavailable && $0.state != "unknown" }
        guard !lamps.isEmpty else { return }
        let state = lamps.contains { $0.state == "on" } ? "on" : "off"
        guard group.state != state else { return }
        group.state = state
        entities[groupId] = group
        if favorites.contains(groupId) { favoritesChanged = true }
    }

    // MARK: Commands

    func showDetail(_ entityId: String) {
        presentedDetail = DetailItem(id: entityId)
    }

    /// Tap on a tile: switches immediately and rolls back if HA rejects the command.
    func tap(_ entity: HAEntity) {
        guard let action = entity.tapAction() else { return }
        Haptics.tap()
        if entity.kind == .scene { flash(entity.entityId) }
        perform(action.call, predicted: action.predicted)
    }

    /// Sends a service call; `predicted` is shown right away and reverted if nothing confirms it.
    func perform(_ call: ServiceCall, predicted: HAEntity? = nil) {
        let entityId = call.entityId
        if let predicted, let current = entities[entityId] {
            let original = pending.removeValue(forKey: entityId).map { change in
                change.timeout.cancel()
                return change.original
            } ?? current
            entities[entityId] = predicted
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.revert(entityId)
            }
            pending[entityId] = PendingChange(original: original, timeout: timeout)
        }

        Task {
            do {
                try await client.send("call_service", call.websocketPayload)
            } catch {
                revert(entityId)
                Haptics.error()
                showError(error.localizedDescription)
            }
        }
    }

    private func revert(_ entityId: String) {
        guard let change = pending.removeValue(forKey: entityId) else { return }
        change.timeout.cancel()
        withAnimation(.snappy) { entities[entityId] = change.original }
    }

    private func flash(_ entityId: String) {
        recentlyActivated.insert(entityId)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            recentlyActivated.remove(entityId)
        }
    }

    /// Sets an `input_number` (e.g. Wunschtemperatur, Temperatur Abwesend).
    func setValue(_ entity: HAEntity, to value: Double) {
        var predicted = entity
        predicted.state = String(value)
        perform(ServiceCall(domain: entity.domain, service: "set_value", entityId: entity.entityId, data: ["value": .number(value)]), predicted: predicted)
    }

    /// Selects an option of an `input_select` (e.g. Heizmodus).
    func selectOption(_ entity: HAEntity, _ option: String) {
        var predicted = entity
        predicted.state = option
        perform(ServiceCall(domain: entity.domain, service: "select_option", entityId: entity.entityId, data: ["option": .string(option)]), predicted: predicted)
    }

    /// Sets the time of an `input_datetime` that has no date.
    func setTime(_ entity: HAEntity, hour: Int, minute: Int) {
        let time = String(format: "%02d:%02d:00", hour, minute)
        var predicted = entity
        predicted.state = time
        predicted.attributes["hour"] = .number(Double(hour))
        predicted.attributes["minute"] = .number(Double(minute))
        perform(ServiceCall(domain: entity.domain, service: "set_datetime", entityId: entity.entityId, data: ["time": .string(time)]), predicted: predicted)
    }

    /// Sets the heater fan speed. A speed above 0 also switches the plug on, otherwise the fans would not run.
    func setFanSpeed(_ fan: RoomFan, to value: Double) {
        Haptics.tap()
        setValue(fan.speed, to: value)
        if value > 0, !fan.isPowered { setFanPower(fan, on: true) }
    }

    /// Switches the plug of the heater fans.
    func setFanPower(_ fan: RoomFan, on: Bool) {
        guard let power = fan.power, !power.isUnavailable else { return }
        Haptics.tap()
        var predicted = power
        predicted.state = on ? "on" : "off"
        perform(.power(entityId: power.entityId, on: on), predicted: predicted)
    }

    /// Turns the "Heizungslüfter" automation on or off. Turning it on also runs it once, so the fans
    /// follow the room's heat demand right away instead of at the next change.
    func setFanAutomatic(_ fan: RoomFan, on: Bool) {
        guard let automation = fan.automation else { return }
        Haptics.tap()
        var predicted = automation
        predicted.state = on ? "on" : "off"
        perform(.power(entityId: automation.entityId, on: on), predicted: predicted)
        if on { perform(ServiceCall(domain: "automation", service: "trigger", entityId: automation.entityId)) }
    }

    /// Switches all given lights on or off at once.
    func setLights(_ lights: [HAEntity], on: Bool) {
        Haptics.tap()
        for light in lights where !light.isUnavailable && (light.state == "on") != on {
            var predicted = light
            predicted.state = on ? "on" : "off"
            perform(.power(entityId: light.entityId, on: on), predicted: predicted)
        }
    }

    /// Numeric history of the given entities (e.g. humidity of the last 24 hours).
    func history(of entityIds: [String], hours: Int) async throws -> [String: [HistoryPoint]] {
        try await stateHistory(of: entityIds, hours: hours).mapValues { changes in
            changes.compactMap { change in Double(change.state).map { HistoryPoint(date: change.date, value: $0) } }
        }
    }

    /// Raw state changes, also for text sensors like "good" / "moderate".
    func stateHistory(of entityIds: [String], hours: Int) async throws -> [String: [StateChange]] {
        let start = Date.now.addingTimeInterval(-Double(hours) * 3600)
        let result = try await client.send("history/history_during_period", [
            "start_time": .string(start.ISO8601Format()),
            "entity_ids": .array(entityIds.map { .string($0) }),
            "minimal_response": true,
            "no_attributes": true,
        ])
        var history: [String: [StateChange]] = [:]
        for id in entityIds {
            history[id] = (result[id]?.array ?? []).compactMap { item in
                guard let state = item["s"]?.string, let time = (item["lu"] ?? item["lc"])?.double else { return nil }
                return StateChange(date: Date(timeIntervalSince1970: time), state: state)
            }
        }
        return history
    }

    private func scheduleConnectionBanner() {
        guard connectionBannerTask == nil, !isConnectionProblemVisible else { return }
        connectionBannerTask = Task {
            try? await Task.sleep(for: Self.connectionBannerDelay)
            guard !Task.isCancelled else { return }
            isConnectionProblemVisible = true
        }
    }

    private func hideConnectionBanner() {
        connectionBannerTask?.cancel()
        connectionBannerTask = nil
        isConnectionProblemVisible = false
    }

    func showError(_ message: String) {
        transientError = message
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            transientError = nil
        }
    }

    // MARK: Favorites

    func isFavorite(_ entityId: String) -> Bool { favorites.contains(entityId) }

    func toggleFavorite(_ entityId: String) {
        if let index = favorites.firstIndex(of: entityId) {
            favorites.remove(at: index)
        } else {
            favorites.append(entityId)
        }
        saveFavorites()
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }

    private func saveFavorites() {
        SharedStorage.favorites = favorites
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.favorites)
    }

    var favoriteEntities: [HAEntity] { favorites.compactMap { entities[$0] } }

    // MARK: Room order

    func moveRooms(from source: IndexSet, to destination: Int) {
        var ids = rooms.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        roomOrder = ids
        SharedStorage.roomOrder = ids
    }

    // MARK: Shared cache for widget & Siri

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        SharedStorage.cachedDevices = entities.values
            .filter { $0.kind != .unsupported && !hiddenEntities.contains($0.entityId) && !categorizedEntities.contains($0.entityId) }
            .map { CachedDevice(entity: $0, areaName: areaName(for: $0.entityId)) }
        if favoritesChanged {
            favoritesChanged = false
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.favorites)
        }
    }
}

struct HistoryPoint: Hashable, Sendable {
    let date: Date
    let value: Double
}

struct StateChange: Hashable, Sendable {
    let date: Date
    let state: String
}

// MARK: - Registry entries

private struct AreaEntry: Decodable {
    let areaId: String
    let name: String
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case areaId = "area_id", name, icon
    }
}

private struct DeviceEntry: Decodable {
    let id: String
    let areaId: String?

    enum CodingKeys: String, CodingKey {
        case id, areaId = "area_id"
    }
}

private struct EntityEntry: Decodable {
    let entityId: String
    let areaId: String?
    let deviceId: String?
    let entityCategory: String?
    let hiddenBy: String?
    let disabledBy: String?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id", areaId = "area_id", deviceId = "device_id"
        case entityCategory = "entity_category", hiddenBy = "hidden_by", disabledBy = "disabled_by"
    }
}
