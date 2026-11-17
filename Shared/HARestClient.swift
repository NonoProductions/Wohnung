import Foundation
import Network
import os

enum HAError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case unauthorized
    case notReachable
    case disconnected
    case http(Int)
    case server(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Home Assistant ist noch nicht eingerichtet."
        case .invalidURL: "Die Adresse ist ungültig."
        case .unauthorized: "Der Token wurde abgelehnt."
        case .notReachable: "Home Assistant ist nicht erreichbar."
        case .disconnected: "Keine Verbindung zu Home Assistant."
        case .http(let code): "Home Assistant antwortet mit Fehler \(code)."
        case .server(let message): message
        case .keychain(let status): "Der Token konnte nicht gespeichert werden (\(status))."
        }
    }
}

/// Picks the right Home Assistant address: local URL on Wi-Fi, external URL otherwise.
enum ServerResolver {
    /// Whether the device currently uses Wi-Fi (or Ethernet) instead of cellular.
    static func isOnLocalNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let resumed = OSAllocatedUnfairLock(initialState: false)
            monitor.pathUpdateHandler = { path in
                let alreadyResumed = resumed.withLock { value in
                    defer { value = true }
                    return value
                }
                guard !alreadyResumed else { return }
                monitor.cancel()
                continuation.resume(returning: isLocal(path))
            }
            monitor.start(queue: DispatchQueue(label: "Zuhause.PathCheck"))
        }
    }

    static func isLocal(_ path: NWPath) -> Bool {
        path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
    }

    /// URLs to try, in order of preference. The other URL stays as fallback (e.g. VPN or weak Wi-Fi).
    static func candidates(for configuration: ServerConfiguration) async -> [URL] {
        let local = configuration.localURL
        let external = configuration.externalURL
        let ordered = await isOnLocalNetwork() ? [local, external] : [external, local]
        return ordered.compactMap { $0 }
    }

    /// Short timeout for local addresses so we fail over quickly when away from home.
    static func timeout(for url: URL, configuration: ServerConfiguration) -> TimeInterval {
        url == configuration.localURL ? 5 : 15
    }
}

/// Minimal REST client, used where a WebSocket is overkill: setup check, widget and Siri.
struct HARestClient: Sendable {
    let baseURL: URL
    let token: String

    /// Finds a reachable address using the stored configuration and token.
    static func resolve() async throws -> HARestClient {
        guard let configuration = SharedStorage.serverConfiguration, let token = TokenStore.load() else {
            throw HAError.notConfigured
        }
        return try await resolve(configuration: configuration, token: token)
    }

    static func resolve(configuration: ServerConfiguration, token: String) async throws -> HARestClient {
        var lastError: Error = HAError.notReachable
        for url in await ServerResolver.candidates(for: configuration) {
            let client = HARestClient(baseURL: url, token: token)
            do {
                try await client.checkAPI(timeout: ServerResolver.timeout(for: url, configuration: configuration))
                return client
            } catch HAError.unauthorized {
                throw HAError.unauthorized
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// `GET /api/` – verifies reachability and the token.
    func checkAPI(timeout: TimeInterval) async throws {
        _ = try await request("api/", method: "GET", body: nil, timeout: timeout)
    }

    func states() async throws -> [HAEntity] {
        let data = try await request("api/states", method: "GET", body: nil, timeout: 10)
        return try JSONDecoder().decode([HAEntity].self, from: data)
    }

    /// Calls a service and returns the states that changed while it ran.
    @discardableResult
    func call(_ call: ServiceCall) async throws -> [HAEntity] {
        let body = try JSONEncoder().encode(JSONValue.object(call.restBody))
        let data = try await request("api/services/\(call.domain)/\(call.service)", method: "POST", body: body, timeout: 10)
        return (try? JSONDecoder().decode([HAEntity].self, from: data)) ?? []
    }

    private func request(_ path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HAError.notReachable
        }
        guard let http = response as? HTTPURLResponse else { throw HAError.notReachable }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw HAError.unauthorized
        default:
            if let message = try? JSONDecoder().decode(JSONValue.self, from: data)["message"]?.string {
                throw HAError.server(message)
            }
            throw HAError.http(http.statusCode)
        }
    }
}
