import Foundation
import CasinoCore
import CasinoNet

/// Zentrale, autoritative Spielinstanz. Ein Actor: Alle Zustandsänderungen laufen
/// nacheinander ab – keine Wettläufe zwischen gleichzeitigen Aktionen.
///
/// Der Server ist die Quelle der Wahrheit für Kartenausgabe, Einsätze, Pot, Gewinner,
/// Ergebnisse und Online-Kontostände. Clients senden nur Absichten.
public actor GameServer {
    public typealias Sink = @Sendable (ServerMessage) -> Void

    private struct Connection {
        let send: Sink
        var playerID: String?
        var recentMessages: [Date] = []
    }

    private struct Room {
        let code: String
        var game: OnlineGame
        var hostID: String
        var memberIDs: [String]
        var status: RoomStatus
        var tableID: String?
    }

    private struct QueueEntry {
        let playerID: String
        let game: OnlineGame
        let since: Date
        var offerToken: UUID
    }

    let config: ServerConfig
    let accounts: AccountStore
    private let cardRandom: RandomSource
    private let botRandom: RandomSource

    private var connections: [UUID: Connection] = [:]
    private var connectionByPlayer: [String: UUID] = [:]
    private var rooms: [String: Room] = [:]
    private var roomByPlayer: [String: String] = [:]
    private var tables: [String: TableSession] = [:]
    private var contexts: [String: TableContext] = [:]
    private var tableByPlayer: [String: String] = [:]
    private var queue: [String: QueueEntry] = [:]
    private var graceTokens: [String: UUID] = [:]
    private var saveScheduled = false

    /// - Parameters:
    ///   - dataURL: Datei für Konten (`nil` = nur im Speicher).
    ///   - cardRandom: Zufallsquelle für Karten; standardmäßig der kryptografisch sichere Systemgenerator.
    public init(dataURL: URL?, config: ServerConfig = ServerConfig(),
                cardRandom: RandomSource = SystemRandomSource(), botRandom: RandomSource = SystemRandomSource()) {
        self.config = config
        self.cardRandom = cardRandom
        self.botRandom = botRandom
        accounts = AccountStore(fileURL: dataURL)
        // Tische überleben keinen Neustart: Tisch-Chips gehen zurück auf das Guthaben.
        accounts.refundAllTableChips()
        accounts.saveIfNeeded()
    }

    // MARK: - Verbindungen

    public func connect(send: @escaping Sink) -> UUID {
        let id = UUID()
        connections[id] = Connection(send: send)
        return id
    }

    public func disconnect(_ connectionID: UUID) {
        guard let connection = connections.removeValue(forKey: connectionID) else { return }
        guard let playerID = connection.playerID, connectionByPlayer[playerID] == connectionID else { return }
        connectionByPlayer[playerID] = nil
        queue[playerID] = nil
        if let tableID = tableByPlayer[playerID], let table = tables[tableID] {
            table.setConnected(playerID, false)
            afterTableChange(tableID)
        }
        notifyFriendsOfPresence(playerID)
        // Kurze Gnadenfrist für die Wiederverbindung; danach verlässt der Spieler Tisch und Raum.
        let token = UUID()
        graceTokens[playerID] = token
        let grace = config.reconnectGrace
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            await self?.graceExpired(playerID, token: token)
        }
    }

    private func graceExpired(_ playerID: String, token: UUID) {
        guard graceTokens[playerID] == token, connectionByPlayer[playerID] == nil else { return }
        graceTokens[playerID] = nil
        leaveTable(playerID, reason: "Verbindung verloren")
        leaveRoom(playerID)
    }

    /// Verarbeitet eine Textnachricht eines Clients.
    public func receive(_ text: String, from connectionID: UUID) {
        guard var connection = connections[connectionID] else { return }
        // Einfaches Rate-Limit gegen Flut/Manipulation
        let now = Date()
        connection.recentMessages = connection.recentMessages.filter { now.timeIntervalSince($0) < 1 } + [now]
        connections[connectionID] = connection
        guard connection.recentMessages.count <= config.maxMessagesPerSecond else {
            if connection.recentMessages.count == config.maxMessagesPerSecond + 1 {
                connection.send(.error(ServerError(code: .rateLimited, message: "Zu viele Anfragen.")))
            }
            return
        }
        guard let message = try? WireCodec.decode(ClientMessage.self, from: text) else {
            connection.send(.error(ServerError(code: .invalidRequest, message: "Ungültige Nachricht.")))
            return
        }
        handle(message, from: connectionID)
    }

    private func send(_ message: ServerMessage, to playerID: String) {
        guard let cid = connectionByPlayer[playerID] else { return }
        connections[cid]?.send(message)
    }

    private func sendError(_ code: ServerErrorCode, _ text: String, to connectionID: UUID) {
        connections[connectionID]?.send(.error(ServerError(code: code, message: text)))
    }

    // MARK: - Nachrichten

    private func handle(_ message: ClientMessage, from cid: UUID) {
        if case .hello(let hello) = message { return handleHello(hello, from: cid) }
        if case .ping = message { connections[cid]?.send(.pong); return }
        guard let playerID = connections[cid]?.playerID else {
            return sendError(.notAuthenticated, "Bitte zuerst anmelden.", to: cid)
        }

        switch message {
        case .hello, .ping:
            break
        case .rename(let name):
            accounts.rename(playerID, to: name)
            sendAccount(playerID)
            notifyFriendsOfPresence(playerID)
        case .addFriend(let code):
            guard let friend = accounts.account(friendCode: code), friend.id != playerID else {
                return sendError(.friendNotFound, "Kein Spieler mit diesem Freundescode gefunden.", to: cid)
            }
            accounts.addFriend(playerID, friendID: friend.id)
            sendFriends(playerID)
            sendFriends(friend.id)
        case .removeFriend(let friendID):
            accounts.removeFriend(playerID, friendID: friendID)
            sendFriends(playerID)
            sendFriends(friendID)
        case .createRoom(let game):
            createRoom(playerID, game: game, cid: cid)
        case .joinRoom(let code):
            joinRoom(playerID, code: code, cid: cid)
        case .setRoomGame(let game):
            setRoomGame(playerID, game: game, cid: cid)
        case .startRoom:
            startRoom(playerID, cid: cid)
        case .leaveRoom:
            leaveRoom(playerID)
            send(.room(nil), to: playerID)
        case .inviteFriend(let friendID):
            invite(playerID, friendID: friendID, cid: cid)
        case .findMatch(let game):
            findMatch(playerID, game: game, cid: cid)
        case .matchWithBots:
            matchWithBots(playerID)
        case .keepWaiting:
            keepWaiting(playerID)
        case .cancelMatch:
            queue[playerID] = nil
            send(.matchmaking(.idle), to: playerID)
        case .tableAction(let request):
            guard let tableID = tableByPlayer[playerID], let table = tables[tableID] else {
                return sendError(.notAtTable, "Du sitzt an keinem Tisch.", to: cid)
            }
            let result = table.handle(request, from: playerID)
            send(.actionResult(result), to: playerID)
            afterTableChange(tableID)
        case .leaveTable:
            leaveTable(playerID, reason: "Tisch verlassen")
        case .claimOnlineRescue:
            if accounts.claimRescue(playerID) {
                sendAccount(playerID)
            } else {
                sendError(.insufficientChips, "Das Startpaket gibt es nur bei fast leerem Online-Konto (höchstens einmal pro Stunde).", to: cid)
            }
        }
    }

    private func handleHello(_ hello: HelloRequest, from cid: UUID) {
        guard hello.protocolVersion == blackCasinoProtocolVersion else {
            return sendError(.protocolMismatch, "Bitte aktualisiere die App.", to: cid)
        }
        var issuedToken: String?
        let account: Account
        if let token = hello.token, let existing = accounts.authenticate(token: token) {
            account = existing
        } else {
            let (created, token) = accounts.register(displayName: hello.displayName)
            account = created
            issuedToken = token
        }
        // Eine bestehende Verbindung desselben Spielers wird ersetzt (Wiederverbindung).
        if let old = connectionByPlayer[account.id], old != cid {
            connections[old]?.playerID = nil
        }
        connections[cid]?.playerID = account.id
        connectionByPlayer[account.id] = cid
        graceTokens[account.id] = nil

        send(.welcome(AccountInfo(player: account.info, onlineChips: account.chips, token: issuedToken)), to: account.id)
        sendFriends(account.id)
        if let code = roomByPlayer[account.id] { send(.room(roomInfo(code)), to: account.id) }
        if let tableID = tableByPlayer[account.id], let table = tables[tableID] {
            table.setConnected(account.id, true)
            afterTableChange(tableID)
        }
        notifyFriendsOfPresence(account.id)
        scheduleSave()
    }

    // MARK: - Konto & Freunde

    private func sendAccount(_ playerID: String) {
        guard let a = accounts.account(playerID) else { return }
        send(.account(AccountInfo(player: a.info, onlineChips: a.chips, token: nil)), to: playerID)
        scheduleSave()
    }

    private func presence(of playerID: String) -> Presence {
        guard connectionByPlayer[playerID] != nil else { return .offline }
        return tableByPlayer[playerID] != nil ? .inGame : .online
    }

    private func sendFriends(_ playerID: String) {
        guard let account = accounts.account(playerID) else { return }
        let list = account.friends.compactMap { accounts.account($0) }
            .map { FriendInfo(player: $0.info, presence: presence(of: $0.id)) }
            .sorted { $0.player.displayName.localizedCaseInsensitiveCompare($1.player.displayName) == .orderedAscending }
        send(.friends(list), to: playerID)
    }

    private func notifyFriendsOfPresence(_ playerID: String) {
        guard let account = accounts.account(playerID) else { return }
        for friend in account.friends where connectionByPlayer[friend] != nil { sendFriends(friend) }
    }

    // MARK: - Private Räume

    private func roomInfo(_ code: String) -> RoomInfo? {
        guard let room = rooms[code] else { return nil }
        let members = room.memberIDs.compactMap { accounts.account($0)?.info }
        return RoomInfo(code: code, game: room.game, hostID: room.hostID, members: members, status: room.status)
    }

    private func broadcastRoom(_ code: String) {
        guard let room = rooms[code], let info = roomInfo(code) else { return }
        for member in room.memberIDs { send(.room(info), to: member) }
    }

    private func isBusy(_ playerID: String) -> Bool {
        roomByPlayer[playerID] != nil || tableByPlayer[playerID] != nil || queue[playerID] != nil
    }

    private func createRoom(_ playerID: String, game: OnlineGame, cid: UUID) {
        guard !isBusy(playerID) else { return sendError(.alreadyInRoom, "Du bist bereits in einem Raum, Spiel oder in der Suche.", to: cid) }
        var code: String
        repeat { code = RoomCode.generate() } while rooms[code] != nil
        rooms[code] = Room(code: code, game: game, hostID: playerID, memberIDs: [playerID], status: .waiting)
        roomByPlayer[playerID] = code
        broadcastRoom(code)
    }

    private func joinRoom(_ playerID: String, code input: String, cid: UUID) {
        guard let code = RoomCode.normalize(input), var room = rooms[code] else {
            return sendError(.roomNotFound, "Kein Raum mit diesem Code gefunden.", to: cid)
        }
        if room.memberIDs.contains(playerID) { return broadcastRoom(code) }
        guard !isBusy(playerID) else { return sendError(.alreadyInRoom, "Verlasse zuerst deinen aktuellen Raum oder Tisch.", to: cid) }
        guard room.status == .waiting else { return sendError(.roomAlreadyStarted, "Dieses Spiel hat bereits begonnen.", to: cid) }
        guard room.memberIDs.count < room.game.maxPlayers else { return sendError(.roomFull, "Der Raum ist voll.", to: cid) }
        room.memberIDs.append(playerID)
        rooms[code] = room
        roomByPlayer[playerID] = code
        broadcastRoom(code)
    }

    private func setRoomGame(_ playerID: String, game: OnlineGame, cid: UUID) {
        guard let code = roomByPlayer[playerID], var room = rooms[code] else { return }
        guard room.hostID == playerID else { return sendError(.notHost, "Nur der Host kann das Spiel wählen.", to: cid) }
        guard room.memberIDs.count == 1, room.status == .waiting else {
            return sendError(.invalidRequest, "Das Spiel kann nur gewechselt werden, solange noch niemand beigetreten ist.", to: cid)
        }
        room.game = game
        rooms[code] = room
        broadcastRoom(code)
    }

    private func startRoom(_ playerID: String, cid: UUID) {
        guard let code = roomByPlayer[playerID], var room = rooms[code] else { return }
        guard room.hostID == playerID else { return sendError(.notHost, "Nur der Host kann das Spiel starten.", to: cid) }
        guard room.status == .waiting, room.memberIDs.count >= room.game.minPlayers else {
            return sendError(.notEnoughPlayers, "Es werden mindestens \(room.game.minPlayers) Spieler benötigt.", to: cid)
        }
        let tableID = createTable(game: room.game, isPrivate: true)
        guard let table = tables[tableID] else { return }
        var seated: [String] = []
        for member in room.memberIDs {
            guard let info = accounts.account(member)?.info else { continue }
            do {
                try table.addHuman(info)
                tableByPlayer[member] = tableID
                seated.append(member)
            } catch {
                send(.notice("\(info.displayName) hat nicht genug Online-Chips für das Buy-in."), to: member)
            }
        }
        guard seated.count >= room.game.minPlayers else {
            // Start nicht möglich: alle wieder aufstehen lassen, Chips zurück
            for member in seated { table.remove(member); tableByPlayer[member] = nil }
            drainContext(tableID)
            closeTable(tableID, reason: nil)
            return sendError(.notEnoughPlayers, "Nicht genug Spieler mit ausreichend Online-Chips.", to: cid)
        }
        room.status = .inGame
        room.tableID = tableID
        rooms[code] = room
        broadcastRoom(code)
        table.start()
        afterTableChange(tableID)
        for member in seated { notifyFriendsOfPresence(member) }
    }

    private func leaveRoom(_ playerID: String) {
        guard let code = roomByPlayer.removeValue(forKey: playerID), var room = rooms[code] else { return }
        room.memberIDs.removeAll { $0 == playerID }
        if room.memberIDs.isEmpty {
            rooms[code] = nil
            return
        }
        if room.hostID == playerID { room.hostID = room.memberIDs[0] }
        rooms[code] = room
        broadcastRoom(code)
    }

    private func invite(_ playerID: String, friendID: String, cid: UUID) {
        guard let code = roomByPlayer[playerID], let room = rooms[code], let me = accounts.account(playerID) else {
            return sendError(.roomNotFound, "Erstelle zuerst einen Raum.", to: cid)
        }
        guard me.friends.contains(friendID) else { return sendError(.friendNotFound, "Dieser Spieler ist nicht in deiner Freundesliste.", to: cid) }
        guard connectionByPlayer[friendID] != nil else { return sendError(.friendNotFound, "Dein Freund ist gerade offline.", to: cid) }
        send(.invitation(Invitation(roomCode: code, game: room.game, from: me.info)), to: friendID)
        send(.notice("Einladung an \(accounts.account(friendID)?.displayName ?? "Freund") gesendet."), to: playerID)
    }

    // MARK: - Matchmaking

    /// Priorität: 1. öffentlicher Tisch mit echten Spielern und freiem Platz,
    /// 2. wartender Spieler für dasselbe Spiel, 3. nach kurzer Wartezeit Bots anbieten.
    private func findMatch(_ playerID: String, game: OnlineGame, cid: UUID) {
        guard !isBusy(playerID) else { return sendError(.alreadyInRoom, "Du bist bereits in einem Raum, Spiel oder in der Suche.", to: cid) }

        if let tableID = tables.first(where: { _, t in
            t.game == game && !t.isPrivate && t.hasFreeSeat && t.hasConnectedHuman
        })?.key {
            if seat(playerID, at: tableID) { return }
        }

        if let partner = queue.values.filter({ $0.game == game && $0.playerID != playerID }).min(by: { $0.since < $1.since }) {
            queue[partner.playerID] = nil
            let tableID = createTable(game: game, isPrivate: false)
            let a = seat(partner.playerID, at: tableID)
            let b = seat(playerID, at: tableID)
            if a || b { tables[tableID]?.start(); afterTableChange(tableID) }
            if !a && !b { closeTable(tableID, reason: nil) }
            if !b { enqueue(playerID, game: game) }
            return
        }
        enqueue(playerID, game: game)
    }

    private func enqueue(_ playerID: String, game: OnlineGame) {
        let entry = QueueEntry(playerID: playerID, game: game, since: Date(), offerToken: UUID())
        queue[playerID] = entry
        send(.matchmaking(.searching(game: game, since: entry.since)), to: playerID)
        scheduleOffer(playerID, token: entry.offerToken)
    }

    private func scheduleOffer(_ playerID: String, token: UUID) {
        let delay = config.matchmakingOfferAfter
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.offerBots(playerID, token: token)
        }
    }

    private func offerBots(_ playerID: String, token: UUID) {
        guard let entry = queue[playerID], entry.offerToken == token else { return }
        send(.matchmaking(.noMatchFound(game: entry.game)), to: playerID)
    }

    private func keepWaiting(_ playerID: String) {
        guard var entry = queue[playerID] else { return }
        entry.offerToken = UUID()
        queue[playerID] = entry
        send(.matchmaking(.searching(game: entry.game, since: entry.since)), to: playerID)
        scheduleOffer(playerID, token: entry.offerToken)
    }

    private func matchWithBots(_ playerID: String) {
        guard let entry = queue.removeValue(forKey: playerID) else { return }
        let tableID = createTable(game: entry.game, isPrivate: false)
        guard seat(playerID, at: tableID, startIfNeeded: false), let table = tables[tableID] else {
            closeTable(tableID, reason: nil)
            return
        }
        for _ in 0..<(entry.game == .poker ? 3 : 2) { table.addBot() }
        table.start()
        afterTableChange(tableID)
    }

    /// Setzt einen Spieler an einen Tisch. Gibt `false` zurück, wenn das nicht möglich war.
    @discardableResult
    private func seat(_ playerID: String, at tableID: String, startIfNeeded: Bool = true) -> Bool {
        guard let table = tables[tableID], let info = accounts.account(playerID)?.info else { return false }
        do {
            try table.addHuman(info)
        } catch TableJoinError.insufficientChips {
            send(.error(ServerError(code: .insufficientChips, message: "Nicht genug Online-Chips für das Buy-in.")), to: playerID)
            send(.matchmaking(.idle), to: playerID)
            return false
        } catch {
            return false
        }
        tableByPlayer[playerID] = tableID
        send(.matchmaking(.matched(tableID: tableID)), to: playerID)
        if startIfNeeded { table.start() }
        afterTableChange(tableID)
        notifyFriendsOfPresence(playerID)
        return true
    }

    // MARK: - Tische

    private func createTable(game: OnlineGame, isPrivate: Bool) -> String {
        let tableID = UUID().uuidString
        let context = TableContext(wallet: accounts, config: config, cardRandom: cardRandom, botRandom: botRandom)
        context.scheduleTimer = { [weak self] timerID, delay in
            Task { [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                await self?.timerFired(tableID: tableID, timerID: timerID)
            }
        }
        contexts[tableID] = context
        tables[tableID] = game == .poker
            ? PokerSession(id: tableID, isPrivate: isPrivate, context: context)
            : BlackjackSession(id: tableID, isPrivate: isPrivate, context: context)
        return tableID
    }

    private func timerFired(tableID: String, timerID: Int) {
        guard let table = tables[tableID] else { return }
        table.timerFired(timerID)
        afterTableChange(tableID)
    }

    private func leaveTable(_ playerID: String, reason: String) {
        guard let tableID = tableByPlayer.removeValue(forKey: playerID) else { return }
        tables[tableID]?.remove(playerID)
        send(.tableClosed(reason: reason), to: playerID)
        afterTableChange(tableID)
        notifyFriendsOfPresence(playerID)
    }

    /// Nach jeder Änderung: Kontostände melden, Abgänge verarbeiten, Zustand an alle senden.
    private func afterTableChange(_ tableID: String) {
        drainContext(tableID)
        guard let table = tables[tableID] else { return }
        for playerID in table.humanIDs where tableByPlayer[playerID] == tableID {
            send(.table(table.snapshot(for: playerID)), to: playerID)
        }
        // Tisch ohne zugeordnete Menschen wird geschlossen (Bots spielen nie allein weiter).
        // Laufende Runden verlassender Spieler werden vorher regulär abgerechnet.
        if !table.humanIDs.contains(where: { tableByPlayer[$0] == tableID }) {
            closeTable(tableID, reason: nil)
        }
    }

    private func drainContext(_ tableID: String) {
        guard let context = contexts[tableID] else { return }
        let touched = context.touchedAccounts
        context.touchedAccounts = []
        for playerID in touched { sendAccount(playerID) }
        context.departed = []
        scheduleSave()
    }

    private func closeTable(_ tableID: String, reason: String?) {
        guard let table = tables[tableID] else { return }
        // Verbleibende Menschen (z. B. noch in Abrechnung) austragen
        for playerID in table.humanIDs { table.remove(playerID) }
        drainContext(tableID)
        if table.humanIDs.isEmpty {
            tables[tableID] = nil
            contexts[tableID] = nil
        }
        for (code, room) in rooms where room.tableID == tableID {
            for member in room.memberIDs {
                roomByPlayer[member] = nil
                send(.room(nil), to: member)
                if let reason { send(.tableClosed(reason: reason), to: member) }
            }
            rooms[code] = nil
        }
    }

    // MARK: - Speicherung

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.performSave()
        }
    }

    private func performSave() {
        saveScheduled = false
        accounts.saveIfNeeded()
    }

    /// Für den geordneten Shutdown.
    public func flush() {
        accounts.saveIfNeeded()
    }

    // MARK: - Einblick für Tests

    func tableID(of playerID: String) -> String? { tableByPlayer[playerID] }
    func onlineChips(of playerID: String) -> (free: Int, table: Int)? {
        accounts.account(playerID).map { ($0.chips, $0.tableChips) }
    }
    var openTableCount: Int { tables.count }
}
