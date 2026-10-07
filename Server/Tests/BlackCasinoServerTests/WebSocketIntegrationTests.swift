import Foundation
import XCTest
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import CasinoNet
@testable import BlackCasinoServerCore

/// Ende-zu-Ende über eine echte WebSocket-Verbindung (HTTP-Upgrade, JSON-Nachrichten).
final class WebSocketIntegrationTests: XCTestCase {
    func testHelloCreateRoomOverRealWebSocket() async throws {
        let server = makeServer()
        let app = ServerApp.makeApplication(server: server, host: "127.0.0.1", port: 0)
        try await app.test(.live) { client in
            let response = try await client.execute(uri: "/health", method: .get)
            XCTAssertEqual(response.status, .ok)

            let received = ReceivedMessages()
            try await client.ws("/ws") { inbound, outbound, _ in
                try await outbound.write(.text(try WireCodec.encode(ClientMessage.hello(HelloRequest(token: nil, displayName: "Kim")))))
                var iterator = inbound.messages(maxSize: WireCodec.maxMessageBytes).makeAsyncIterator()
                while let message = try await iterator.next() {
                    guard case .text(let text) = message, let decoded = try? WireCodec.decode(ServerMessage.self, from: text) else { continue }
                    received.append(decoded)
                    switch decoded {
                    case .welcome:
                        try await outbound.write(.text(try WireCodec.encode(ClientMessage.createRoom(game: .poker))))
                    case .room(let room?):
                        XCTAssertEqual(room.code.count, 6)
                        try await outbound.write(.text(try WireCodec.encode(ClientMessage.ping)))
                    case .pong:
                        try await outbound.close(.normalClosure, reason: nil)
                        return
                    default:
                        break
                    }
                }
            }
            XCTAssertTrue(received.all.contains { if case .welcome(let a) = $0 { return a.token != nil } else { return false } })
            XCTAssertTrue(received.all.contains { if case .room(let r) = $0 { return r != nil } else { return false } })
        }
    }
}

final class ReceivedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ServerMessage] = []
    func append(_ m: ServerMessage) { lock.lock(); items.append(m); lock.unlock() }
    var all: [ServerMessage] { lock.lock(); defer { lock.unlock() }; return items }
}
