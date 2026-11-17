import Foundation
import HomeKit
import Observation

/// A scene from Apple Home, run through HomeKit.
struct AppleScene: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    /// The Apple Home room all of its accessories are in, or nil if it spans several rooms.
    let roomName: String?
}

/// Reads the scenes of Apple Home via HomeKit and runs them. Home Assistant scenes are not shown in the app.
@MainActor
@Observable
final class AppleHomeScenes {
    private(set) var scenes: [AppleScene] = []
    /// Scenes that were just run, for a short highlight.
    private(set) var recentlyRun: Set<UUID> = []
    /// False once the user denied access to Apple Home.
    private(set) var isAuthorized = true

    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var actionSets: [UUID: (home: HMHome, actionSet: HMActionSet)] = [:]
    /// Shows an error banner (wired to HomeStore in ZuhauseApp).
    @ObservationIgnored var onError: (@MainActor (String) -> Void)?

    /// Creates the home manager (asks for access on first launch) or reloads the scenes.
    func start() {
        guard manager == nil else { return reload() }
        let delegate = Delegate { [weak self] in
            // Let HomeKit finish its update before reading homes and scenes.
            Task { @MainActor in self?.reload() }
        }
        let manager = HMHomeManager()
        manager.delegate = delegate
        self.delegate = delegate
        self.manager = manager
    }

    /// Scenes for one app room, matched to Apple Home rooms by name ("Wohnzimmer" = "Wohnzimmer").
    func scenes(inRoom name: String) -> [AppleScene] {
        scenes.filter { $0.roomName.map { Self.sameName($0, name) } ?? false }
    }

    /// Scenes that span several rooms or whose room does not exist in the app.
    func otherScenes(roomNames: [String]) -> [AppleScene] {
        scenes.filter { scene in
            guard let room = scene.roomName else { return true }
            return !roomNames.contains { Self.sameName($0, room) }
        }
    }

    func run(_ scene: AppleScene) {
        guard let entry = actionSets[scene.id] else { return }
        Haptics.tap()
        recentlyRun.insert(scene.id)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            recentlyRun.remove(scene.id)
        }
        let id = scene.id
        // HomeKit may call back on any queue, so the block must not be main-actor isolated.
        entry.home.executeActionSet(entry.actionSet) { @Sendable [weak self] error in
            let message = error?.localizedDescription
            Task { @MainActor in self?.finished(id, error: message) }
        }
    }

    private func finished(_ id: UUID, error: String?) {
        guard let error else { return }
        recentlyRun.remove(id)
        Haptics.error()
        onError?("Szene fehlgeschlagen: \(error)")
    }

    private func reload() {
        guard let manager else { return }
        let status = manager.authorizationStatus
        isAuthorized = !status.contains(.determined) || status.contains(.authorized)

        var sets: [UUID: (home: HMHome, actionSet: HMActionSet)] = [:]
        var result: [AppleScene] = []
        for home in manager.homes {
            home.delegate = delegate
            let defaultRoom = home.roomForEntireHome().uniqueIdentifier
            // Scenes that belong to an automation are not shown in Apple Home either.
            for actionSet in home.actionSets where actionSet.actionSetType != HMActionSetTypeTriggerOwned {
                sets[actionSet.uniqueIdentifier] = (home, actionSet)
                let rooms = Set(actionSet.actions.compactMap { action -> HMRoom? in
                    (action as? HMCharacteristicWriteAction<NSCopying>)?.characteristic.service?.accessory?.room
                }.filter { $0.uniqueIdentifier != defaultRoom }.map(\.name))
                result.append(AppleScene(
                    id: actionSet.uniqueIdentifier,
                    name: actionSet.name,
                    symbol: Self.symbol(for: actionSet.actionSetType),
                    roomName: rooms.count == 1 ? rooms.first : nil
                ))
            }
        }
        actionSets = sets
        scenes = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func symbol(for type: String) -> String {
        switch type {
        case HMActionSetTypeWakeUp: "sun.horizon.fill"
        case HMActionSetTypeSleep: "moon.fill"
        case HMActionSetTypeHomeDeparture: "figure.walk.departure"
        case HMActionSetTypeHomeArrival: "house.fill"
        default: "sparkles"
        }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// HomeKit calls its delegates on the main queue; every change simply reloads the scene list.
    @MainActor
    private final class Delegate: NSObject, @preconcurrency HMHomeManagerDelegate, @preconcurrency HMHomeDelegate {
        let onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
        }

        private func changed() { onChange() }

        func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { changed() }
        func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { changed() }
        func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { changed() }
        func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { changed() }
        func home(_ home: HMHome, didAdd actionSet: HMActionSet) { changed() }
        func home(_ home: HMHome, didRemove actionSet: HMActionSet) { changed() }
        func home(_ home: HMHome, didUpdateNameFor actionSet: HMActionSet) { changed() }
        func home(_ home: HMHome, didUpdateActionsFor actionSet: HMActionSet) { changed() }
        func home(_ home: HMHome, didUpdateNameFor room: HMRoom) { changed() }
        func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) { changed() }
    }
}
