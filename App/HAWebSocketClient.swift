import Foundation

/// Home Assistant WebSocket API client (`/api/websocket`).
///
/// Usage: `connect` performs the auth handshake, then `runReceiveLoop` must run for as long as the
/// connection is used; it throws once the socket closes. Commands are sent with `send`.
@MainActor
final class HAWebSocketClient {
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    /// Increments with every `connect`, so stale callers cannot close a newer connection.
    private(set) var connectionID = 0

    /// Called for every `event` message of a subscription.
    var onEvent: ((JSONValue) -> Void)?

    static func websocketURL(for baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased() == "https" ? "wss" : "ws"
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/api/websocket"
        components.query = nil
        return components.url
    }

    /// Opens the socket and authenticates. Throws `HAError.unauthorized` for a bad token.
    func connect(to baseURL: URL, token: String, timeout: TimeInterval) async throws {
        disconnect()
        connectionID += 1
        guard let url = Self.websocketURL(for: baseURL) else { throw HAError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1024 * 1024
        self.task = task
        task.resume()

        // Abort the handshake if the server does not answer in time.
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            task.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel() }

        do {
            let hello = try await receiveMessage(from: task)
            guard hello["type"]?.string == "auth_required" else { throw HAError.server("Unerwartete Antwort vom Server.") }
            try await task.send(.string(Self.encode(["type": "auth", "access_token": .string(token)])))
            let auth = try await receiveMessage(from: task)
            switch auth["type"]?.string {
            case "auth_ok": return
            case "auth_invalid": throw HAError.unauthorized
            default: throw HAError.server("Anmeldung fehlgeschlagen.")
            }
        } catch let error as HAError {
            disconnect()
            throw error
        } catch {
            disconnect()
            throw HAError.notReachable
        }
    }

    /// Reads messages until the socket closes, then fails all outstanding requests.
    func runReceiveLoop() async throws {
        guard let task else { throw HAError.disconnected }
        do {
            while true {
                handle(try await receiveMessage(from: task))
            }
        } catch {
            if self.task === task { disconnect() }
            throw HAError.disconnected
        }
    }

    /// Sends a command and waits for its `result`.
    @discardableResult
    func send(_ type: String, _ payload: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard let task else { throw HAError.disconnected }
        let id = nextID
        nextID += 1
        var message = payload
        message["id"] = .number(Double(id))
        message["type"] = .string(type)
        let text = try Self.encode(message)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    self.pending.removeValue(forKey: id)?.resume(throwing: HAError.disconnected)
                }
            }
        }
    }

    /// Closes the socket only if it still belongs to the given connection.
    func disconnect(connectionID: Int) {
        if connectionID == self.connectionID { disconnect() }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: HAError.disconnected)
        }
    }

    // MARK: Private

    private func handle(_ message: JSONValue) {
        // HA may coalesce several messages into one JSON array.
        if let items = message.array {
            items.forEach(handle)
            return
        }
        switch message["type"]?.string {
        case "event":
            if let event = message["event"] { onEvent?(event) }
        case "result":
            guard let id = message["id"]?.int, let continuation = pending.removeValue(forKey: id) else { return }
            if message["success"]?.bool == true {
                continuation.resume(returning: message["result"] ?? .null)
            } else {
                let text = message["error"]?["message"]?.string ?? "Home Assistant hat den Befehl abgelehnt."
                continuation.resume(throwing: HAError.server(text))
            }
        case "pong":
            guard let id = message["id"]?.int else { return }
            pending.removeValue(forKey: id)?.resume(returning: .null)
        default:
            break
        }
    }

    private func receiveMessage(from task: URLSessionWebSocketTask) async throws -> JSONValue {
        let data: Data
        switch try await task.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return .null
        }
        // A single malformed message must not tear down the connection.
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }

    private static func encode(_ message: [String: JSONValue]) throws -> String {
        String(decoding: try JSONEncoder().encode(JSONValue.object(message)), as: UTF8.self)
    }
}
