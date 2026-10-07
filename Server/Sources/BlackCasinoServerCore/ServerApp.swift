import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import CasinoNet

/// HTTP/WebSocket-Anbindung des `GameServer`.
/// * `GET /health` – Statusprüfung (für Load Balancer/Monitoring)
/// * `GET /ws` – WebSocket mit JSON-Nachrichten (`ClientMessage` / `ServerMessage`)
public enum ServerApp {
    public static func makeApplication(server: GameServer, host: String = "0.0.0.0", port: Int = 8080,
                                       logger: Logger = Logger(label: "BlackCasino")) -> some ApplicationProtocol {
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.get("/health") { _, _ in "ok" }
        router.ws("/ws") { inbound, outbound, _ in
            let (stream, continuation) = AsyncStream<ServerMessage>.makeStream(bufferingPolicy: .bufferingNewest(256))
            let connectionID = await server.connect { message in continuation.yield(message) }
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Ausgehend: Nachrichten des Servers an diesen Client
                group.addTask {
                    for await message in stream {
                        guard let text = try? WireCodec.encode(message) else { continue }
                        try await outbound.write(.text(text))
                    }
                }
                // Eingehend: Nachrichten des Clients
                do {
                    for try await message in inbound.messages(maxSize: WireCodec.maxMessageBytes) {
                        if case .text(let text) = message {
                            await server.receive(text, from: connectionID)
                        }
                    }
                } catch {
                    logger.debug("WebSocket beendet: \(error)")
                }
                await server.disconnect(connectionID)
                continuation.finish()
                group.cancelAll()
            }
        }
        return Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(address: .hostname(host, port: port)),
            logger: logger
        )
    }
}
