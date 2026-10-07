import Foundation
import XCTest
import CasinoCore
import CasinoNet
@testable import BlackCasinoServerCore

/// Simulierter Client: spricht mit dem `GameServer` exakt über die serialisierten Nachrichten.
final class TestClient: @unchecked Sendable {
    let server: GameServer
    private(set) var connectionID: UUID!
    private let lock = NSLock()
    private var inbox: [ServerMessage] = []
    private(set) var token: String?
    private(set) var account: AccountInfo?

    init(server: GameServer) {
        self.server = server
    }

    func connect(name: String, token: String? = nil) async throws {
        connectionID = await server.connect { [weak self] message in self?.deliver(message) }
        try await send(.hello(HelloRequest(token: token ?? self.token, displayName: name)))
        let welcome = try await waitFor { if case .welcome = $0 { return true } else { return false } }
        if case .welcome(let info) = welcome {
            account = info
            if let t = info.token { self.token = t }
        }
    }

    func disconnect() async {
        await server.disconnect(connectionID)
    }

    var playerID: String { account!.player.id }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private func deliver(_ message: ServerMessage) {
        locked { inbox.append(message) }
    }

    func send(_ message: ClientMessage) async throws {
        await server.receive(try WireCodec.encode(message), from: connectionID)
    }

    var messages: [ServerMessage] { locked { inbox } }

    func clear() { locked { inbox.removeAll() } }

    private func take(where predicate: (ServerMessage) -> Bool) -> ServerMessage? {
        locked {
            guard let index = inbox.firstIndex(where: predicate) else { return nil }
            let message = inbox[index]
            inbox.removeFirst(index + 1)
            return message
        }
    }

    /// Wartet auf die erste (neue) Nachricht, die die Bedingung erfüllt, und entfernt alle davor.
    @discardableResult
    func waitFor(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                 _ predicate: (ServerMessage) -> Bool) async throws -> ServerMessage {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let message = take(where: predicate) { return message }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Zeitüberschreitung beim Warten auf Nachricht. Letzte: \(messages.suffix(3))", file: file, line: line)
        throw CancellationError()
    }

    /// Neuester Tischzustand, der die Bedingung erfüllt.
    func waitForTable(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                      _ predicate: (TableSnapshot) -> Bool = { _ in true }) async throws -> TableSnapshot {
        let message = try await waitFor(timeout: timeout, file: file, line: line) {
            if case .table(let snap) = $0 { return predicate(snap) } else { return false }
        }
        guard case .table(let snap) = message else { throw CancellationError() }
        return snap
    }

    var latestTable: TableSnapshot? {
        for message in messages.reversed() { if case .table(let s) = message { return s } }
        return nil
    }

    func error() async throws -> ServerError {
        let m = try await waitFor { if case .error = $0 { return true } else { return false } }
        guard case .error(let e) = m else { throw CancellationError() }
        return e
    }

    func room() async throws -> RoomInfo? {
        let m = try await waitFor { if case .room = $0 { return true } else { return false } }
        guard case .room(let r) = m else { throw CancellationError() }
        return r
    }

    func act(_ action: TableAction, version: Int, id: UUID = UUID()) async throws {
        try await send(.tableAction(TableActionRequest(actionID: id, stateVersion: version, action: action)))
    }

    func actionResult(_ id: UUID) async throws -> ActionResult {
        let m = try await waitFor { if case .actionResult(let r) = $0 { return r.actionID == id } else { return false } }
        guard case .actionResult(let r) = m else { throw CancellationError() }
        return r
    }
}

func makeServer(config: ServerConfig = .testing, seed: UInt64? = nil) -> GameServer {
    if let seed {
        return GameServer(dataURL: nil, config: config, cardRandom: SeededRandomSource(seed: seed),
                          botRandom: SeededRandomSource(seed: seed &+ 1))
    }
    return GameServer(dataURL: nil, config: config)
}
