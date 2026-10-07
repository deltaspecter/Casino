import Foundation
import Observation

/// Client für den BlackCasino-Server (WebSocket).
///
/// Grundsatz: Der Server ist die Quelle der Wahrheit. Dieser Client sendet nur Absichten
/// und zeigt den empfangenen Zustand an. Er erzeugt niemals selbst Karten, Gewinner,
/// Einsätze oder Kontostände – auch nicht bei Verbindungsabbruch.
@MainActor
@Observable
final class OnlineService {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        /// Verbindung verloren, neuer Versuch läuft.
        case reconnecting(attempt: Int)
        /// Wiederverbindung gescheitert.
        case failed(String)
    }

    static let defaultServerURL = "ws://localhost:8080/ws"
    private static let tokenKey = "token"
    private static let serverURLKey = "BlackCasino.serverURL"

    private(set) var state: ConnectionState = .disconnected
    private(set) var account: AccountInfo?
    private(set) var friends: [FriendInfo] = []
    private(set) var room: RoomInfo?
    private(set) var matchmaking: MatchmakingStatus = .idle
    private(set) var table: TableSnapshot?
    private(set) var invitations: [Invitation] = []
    /// Letzter Grund, warum ein Tisch geschlossen wurde (für Hinweise).
    private(set) var tableClosedReason: String?
    private(set) var gate = ActionGate()

    /// Meldungen für die Oberfläche (Fehler, Hinweise).
    @ObservationIgnored var onNotice: (@MainActor (String, Bool) -> Void)?

    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private let policy = ReconnectPolicy()
    @ObservationIgnored private var displayName = "Spieler"
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var lastPong = Date()

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey)
              ?? (Bundle.main.object(forInfoDictionaryKey: "BCServerURL") as? String)
              ?? Self.defaultServerURL }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.serverURLKey)
            if wantsConnection { reconnectNow() }
        }
    }

    var isConnected: Bool { state == .connected }
    var isAtTable: Bool { table != nil }

    // MARK: - Verbindung

    /// Baut die Verbindung auf (idempotent).
    func connect(displayName: String) {
        self.displayName = displayName
        wantsConnection = true
        switch state {
        case .connected, .connecting, .reconnecting: return
        case .disconnected, .failed: open(attempt: nil)
        }
    }

    /// Bewusstes Trennen (App im Hintergrund, Offline erkannt).
    /// Der Server hält den Platz für eine Gnadenfrist, damit eine Rückkehr möglich ist.
    func disconnect() {
        wantsConnection = false
        generation += 1
        pingTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        gate.reset()
        state = .disconnected
    }

    /// Netzwerk ist weg: Zustand behalten, keine neuen Aktionen, später neu verbinden.
    func networkLost() {
        guard wantsConnection else { return }
        generation += 1
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        gate.reset()
        if table != nil || room != nil {
            state = .reconnecting(attempt: 0)
        } else {
            state = .disconnected
        }
    }

    func networkRestored() {
        guard wantsConnection else { return }
        if case .connected = state { return }
        open(attempt: 0)
    }

    private func reconnectNow() {
        generation += 1
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        state = .disconnected
        open(attempt: nil)
    }

    private func open(attempt: Int?) {
        guard let url = URL(string: serverURL), url.scheme == "ws" || url.scheme == "wss" else {
            state = .failed("Ungültige Serveradresse.")
            return
        }
        generation += 1
        let myGeneration = generation
        state = attempt.map { .reconnecting(attempt: $0) } ?? .connecting
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = WireCodec.maxMessageBytes
        socket = task
        task.resume()
        send(.hello(HelloRequest(token: KeychainStore.read(Self.tokenKey), displayName: displayName)))
        Task { await receiveLoop(task, generation: myGeneration, attempt: attempt ?? 0) }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask, generation myGeneration: Int, attempt: Int) async {
        while myGeneration == generation {
            do {
                let message = try await task.receive()
                guard myGeneration == generation else { return }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(decoding: d, as: UTF8.self)
                @unknown default: continue
                }
                guard let decoded = try? WireCodec.decode(ServerMessage.self, from: text) else { continue }
                handle(decoded)
            } catch {
                guard myGeneration == generation else { return }
                connectionDropped(previousAttempt: attempt)
                return
            }
        }
    }

    /// Verbindung abgebrochen: Spielstand bleibt erhalten (nur Anzeige), Aktionen gesperrt,
    /// Wiederverbindung mit wachsenden Pausen. Es werden keine Ergebnisse erfunden.
    private func connectionDropped(previousAttempt: Int) {
        pingTask?.cancel()
        socket = nil
        gate.reset()
        guard wantsConnection else { state = .disconnected; return }
        let attempt = (state == .connected) ? 0 : previousAttempt + 1
        guard let delay = policy.delay(forAttempt: attempt) else {
            state = .failed("Verbindung konnte nicht wiederhergestellt werden.")
            matchmaking = .idle
            return
        }
        state = .reconnecting(attempt: attempt)
        let myGeneration = generation
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard myGeneration == generation, wantsConnection else { return }
            open(attempt: attempt)
        }
    }

    private func startHeartbeat() {
        pingTask?.cancel()
        lastPong = Date()
        let myGeneration = generation
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, myGeneration == self.generation else { return }
                if Date().timeIntervalSince(self.lastPong) > 25 {
                    // Keine Antwort mehr: wie ein Abbruch behandeln
                    self.socket?.cancel(with: .abnormalClosure, reason: nil)
                    return
                }
                self.send(.ping)
            }
        }
    }

    /// Nach endgültigem Verbindungsverlust: lokale Online-Ansichten verlassen.
    func acknowledgeFailure() {
        table = nil
        room = nil
        matchmaking = .idle
        state = .disconnected
        wantsConnection = false
    }

    private func send(_ message: ClientMessage) {
        guard let socket, let text = try? WireCodec.encode(message) else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: - Eingehende Nachrichten

    private func handle(_ message: ServerMessage) {
        switch message {
        case .welcome(let info):
            if let token = info.token { KeychainStore.write(token, for: Self.tokenKey) }
            account = info
            state = .connected
            startHeartbeat()
            if info.player.displayName != displayName { send(.rename(displayName: displayName)) }
        case .account(let info):
            account = info
        case .friends(let list):
            friends = list
        case .room(let info):
            room = info
        case .invitation(let invitation):
            invitations.removeAll { $0.roomCode == invitation.roomCode }
            invitations.append(invitation)
        case .matchmaking(let status):
            matchmaking = status
        case .table(let snapshot):
            // Nur neuere Stände übernehmen – nie zurückspringen
            if let current = table, current.tableID == snapshot.tableID, snapshot.version < current.version { return }
            table = snapshot
            tableClosedReason = nil
        case .tableClosed(let reason):
            table = nil
            tableClosedReason = reason
            gate.reset()
        case .actionResult(let result):
            gate.resolve(result.actionID)
            if !result.accepted, let reason = result.reason { onNotice?(reason, true) }
        case .notice(let text):
            onNotice?(text, false)
        case .error(let error):
            gate.reset()
            onNotice?(error.message, true)
        case .pong:
            lastPong = Date()
        }
    }

    // MARK: - Aktionen (nur Absichten)

    func rename(_ name: String) {
        displayName = name
        if isConnected { send(.rename(displayName: name)) }
    }

    func addFriend(code: String) { send(.addFriend(friendCode: code)) }
    func removeFriend(_ id: String) { send(.removeFriend(playerID: id)) }
    func createRoom(_ game: OnlineGame) { send(.createRoom(game: game)) }
    func setRoomGame(_ game: OnlineGame) { send(.setRoomGame(game: game)) }
    func startRoom() { send(.startRoom) }
    func leaveRoom() { send(.leaveRoom); room = nil }
    func invite(_ friendID: String) { send(.inviteFriend(playerID: friendID)) }
    func claimRescue() { send(.claimOnlineRescue) }

    func joinRoom(code: String) -> Bool {
        guard let normalized = RoomCode.normalize(code) else { return false }
        send(.joinRoom(code: normalized))
        return true
    }

    func accept(_ invitation: Invitation) {
        invitations.removeAll { $0.id == invitation.id }
        send(.joinRoom(code: invitation.roomCode))
    }

    func decline(_ invitation: Invitation) {
        invitations.removeAll { $0.id == invitation.id }
    }

    func findMatch(_ game: OnlineGame) {
        matchmaking = .searching(game: game, since: Date())
        send(.findMatch(game: game))
    }

    func playWithBots() { send(.matchWithBots) }
    func keepWaiting() { send(.keepWaiting) }

    func cancelMatch() {
        send(.cancelMatch)
        matchmaking = .idle
    }

    func leaveTable() {
        send(.leaveTable)
        table = nil
        gate.reset()
        matchmaking = .idle
    }

    /// Sendet eine Tischaktion. Gibt `false` zurück, wenn gerade keine Aktion möglich ist
    /// (offene Aktion, keine Verbindung) – so werden Doppel-Taps verhindert.
    @discardableResult
    func act(_ action: TableAction) -> Bool {
        guard isConnected, let table, let id = gate.begin() else { return false }
        send(.tableAction(TableActionRequest(actionID: id, stateVersion: table.version, action: action)))
        // Sicherheitsnetz: ohne Antwort wird die Sperre nach einigen Sekunden gelöst
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.gate.resolve(id)
        }
        return true
    }

    var canAct: Bool { isConnected && !gate.isBusy }

    func clearClosedReason() { tableClosedReason = nil }
}
