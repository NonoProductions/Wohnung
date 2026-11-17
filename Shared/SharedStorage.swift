import Foundation
import Security

/// Storage shared between the app, the widget and the App Intents via the App Group.
enum SharedStorage {
    static let appGroupID: String =
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group." + (Bundle.main.bundleIdentifier ?? "zuhause").replacingOccurrences(of: ".widget", with: "")

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    private enum Key {
        static let server = "serverConfiguration"
        static let favorites = "favorites"
        static let devices = "deviceCache"
        static let roomOrder = "roomOrder"
    }

    // MARK: Server

    static var serverConfiguration: ServerConfiguration? {
        get {
            guard let data = defaults.data(forKey: Key.server) else { return nil }
            return try? JSONDecoder().decode(ServerConfiguration.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.server)
            } else {
                defaults.removeObject(forKey: Key.server)
            }
        }
    }

    // MARK: Favorites (ordered entity ids)

    static var favorites: [String] {
        get { defaults.stringArray(forKey: Key.favorites) ?? [] }
        set { defaults.set(newValue, forKey: Key.favorites) }
    }

    // MARK: Room order (area ids, "" = "Weitere")

    static var roomOrder: [String] {
        get { defaults.stringArray(forKey: Key.roomOrder) ?? [] }
        set { defaults.set(newValue, forKey: Key.roomOrder) }
    }

    // MARK: Device cache (used by Siri and the widget while the app is not running)

    static var cachedDevices: [CachedDevice] {
        get {
            guard let data = defaults.data(forKey: Key.devices) else { return [] }
            return (try? JSONDecoder().decode([CachedDevice].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.devices)
        }
    }

    /// Updates cached entries with fresh states (e.g. the result of a REST service call).
    static func updateCache(with entities: [HAEntity]) {
        guard !entities.isEmpty else { return }
        let fresh = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { _, last in last })
        cachedDevices = cachedDevices.map { device in
            guard let entity = fresh[device.entity.entityId] else { return device }
            return CachedDevice(entity: entity, areaName: device.areaName)
        }
    }
}

struct ServerConfiguration: Codable, Sendable, Equatable {
    var localURL: URL?
    var externalURL: URL?

    var isComplete: Bool { localURL != nil || externalURL != nil }

    /// Accepts "homeassistant.local:8123" as well as full URLs and strips trailing slashes.
    static func normalize(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }
}

struct CachedDevice: Codable, Sendable, Hashable, Identifiable {
    let entity: HAEntity
    let areaName: String?
    var id: String { entity.entityId }
    var name: String { entity.displayName(inRoom: areaName) }
}

/// The long-lived access token lives in the keychain, never in UserDefaults.
enum TokenStore {
    private static let service = "Zuhause.HomeAssistant"
    private static let account = "long-lived-access-token"

    private static func query(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// Prefer the shared App Group access group so the widget can read the token;
    /// fall back to the app's private keychain if the entitlement is missing.
    private static var accessGroups: [String?] { [SharedStorage.appGroupID, nil] }

    static func save(_ token: String) throws {
        delete()
        var lastStatus: OSStatus = errSecSuccess
        for group in accessGroups {
            var item = query(accessGroup: group)
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            lastStatus = SecItemAdd(item as CFDictionary, nil)
            if lastStatus == errSecSuccess { return }
        }
        throw HAError.keychain(lastStatus)
    }

    static func load() -> String? {
        for group in accessGroups {
            var item = query(accessGroup: group)
            item[kSecReturnData as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let token = String(data: data, encoding: .utf8) {
                return token
            }
        }
        return nil
    }

    static func delete() {
        for group in accessGroups {
            SecItemDelete(query(accessGroup: group) as CFDictionary)
        }
    }
}
