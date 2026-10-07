import Foundation
import CasinoCore
import CasinoNet

/// Zeitvorgaben des Servers (in Tests verkürzt).
public struct ServerConfig: Sendable {
    public var turnTimeout: TimeInterval = 25
    public var bettingWindow: TimeInterval = 12
    public var resultPause: TimeInterval = 4.5
    public var botThinkTime: ClosedRange<Double> = 0.8...1.8
    public var matchmakingOfferAfter: TimeInterval = 12
    public var reconnectGrace: TimeInterval = 60
    public var maxMessagesPerSecond = 30

    public init() {}

    /// Sehr kurze Zeiten für automatisierte Tests.
    public static var testing: ServerConfig {
        var c = ServerConfig()
        c.turnTimeout = 0.6
        c.bettingWindow = 0.3
        c.resultPause = 0.1
        c.botThinkTime = 0.01...0.03
        c.matchmakingOfferAfter = 0.3
        c.reconnectGrace = 0.5
        return c
    }
}

/// Verbindung einer Tisch-Sitzung zum Server: Wallet, Timer und Zufallsquellen.
/// Wird nur innerhalb des `GameServer`-Actors benutzt.
final class TableContext {
    let wallet: AccountStore
    let config: ServerConfig
    /// Zufallsquelle für Karten (kryptografisch sicher). Hängt von nichts anderem ab.
    let cardRandom: RandomSource
    /// Getrennte Quelle für Bot-Verhalten und Bot-Namen – beeinflusst keine Karten.
    let botRandom: RandomSource
    var now: () -> Date = Date.init
    /// Plant einen Timer; nach Ablauf ruft der Server `timerFired(id)` der Sitzung auf.
    var scheduleTimer: (_ id: Int, _ delay: TimeInterval) -> Void = { _, _ in }
    /// Konten, deren Guthaben sich geändert hat (Server schickt Kontostand).
    var touchedAccounts = Set<String>()
    /// Spieler, deren Platz endgültig frei ist.
    var departed: [String] = []

    init(wallet: AccountStore, config: ServerConfig, cardRandom: RandomSource, botRandom: RandomSource) {
        self.wallet = wallet
        self.config = config
        self.cardRandom = cardRandom
        self.botRandom = botRandom
    }
}

enum TableJoinError: Error {
    case full
    case insufficientChips
}

/// Ein Platz am Tisch: Mensch oder Bot.
struct Occupant {
    let player: PlayerInfo
    let isBot: Bool
    let botStyle: PokerStyle?
    var isConnected = true
    /// Verlässt den Tisch, sobald die laufende Runde vorbei ist.
    var isLeaving = false
}

/// Gemeinsame Schnittstelle der autoritativen Tisch-Sitzungen.
protocol TableSession: AnyObject {
    var id: String { get }
    var game: OnlineGame { get }
    var isPrivate: Bool { get }
    var version: Int { get }
    var hasFreeSeat: Bool { get }
    /// Menschen, die aktuell (noch) einen Platz haben.
    var humanIDs: [String] { get }
    var hasConnectedHuman: Bool { get }

    func addHuman(_ player: PlayerInfo) throws
    func addBot()
    func start()
    func snapshot(for playerID: String?) -> TableSnapshot
    func handle(_ request: TableActionRequest, from playerID: String) -> ActionResult
    func setConnected(_ playerID: String, _ connected: Bool)
    func remove(_ playerID: String)
    func timerFired(_ id: Int)
}

/// Merkt sich verarbeitete Aktions-IDs, damit doppelt gesendete Aktionen nichts doppelt bewirken.
struct ActionLedger {
    private var results: [UUID: ActionResult] = [:]
    private var order: [UUID] = []

    func result(for id: UUID) -> ActionResult? { results[id] }

    mutating func record(_ result: ActionResult) {
        results[result.actionID] = result
        order.append(result.actionID)
        if order.count > 500 { results[order.removeFirst()] = nil }
    }
}

enum BotNames {
    static let all = ["Ava", "Leo", "Mia", "Finn", "Zoe", "Max", "Lina", "Tom", "Nora", "Ben", "Ella", "Jan"]

    static func make(random: RandomSource, avoiding used: Set<String>) -> PlayerInfo {
        let free = all.filter { !used.contains("Bot \($0)") }
        let name = "Bot " + (random.pick(free) ?? "\(random.uniform(1000))")
        return PlayerInfo(id: "bot-" + UUID().uuidString, displayName: name, friendCode: "")
    }
}
