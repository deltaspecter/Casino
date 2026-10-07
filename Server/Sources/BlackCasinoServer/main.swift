import Foundation
import Logging
import BlackCasinoServerCore

// Konfiguration über Umgebungsvariablen:
//   PORT      – Port (Standard 8080)
//   DATA_DIR  – Verzeichnis für Kontodaten (Standard ./data)
let environment = ProcessInfo.processInfo.environment
let port = Int(environment["PORT"] ?? "") ?? 8080
let dataDir = URL(fileURLWithPath: environment["DATA_DIR"] ?? "data", isDirectory: true)
var logger = Logger(label: "BlackCasino")
logger.logLevel = .info

let server = GameServer(dataURL: dataDir.appendingPathComponent("accounts.json"))
let app = ServerApp.makeApplication(server: server, port: port, logger: logger)
logger.info("BlackCasino-Server startet auf Port \(port)")
try await app.runService()
await server.flush()
