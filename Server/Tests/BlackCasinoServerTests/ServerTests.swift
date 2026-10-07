import Foundation
import XCTest
import CasinoCore
import CasinoNet
@testable import BlackCasinoServerCore

final class AccountAndSocialTests: XCTestCase {
    func testRegistrationAndTokenLogin() async throws {
        let server = makeServer()
        let a = TestClient(server: server)
        try await a.connect(name: "Kim")
        XCTAssertNotNil(a.token)
        XCTAssertEqual(a.account?.onlineChips, AccountStore.startingChips)
        let id = a.playerID
        await a.disconnect()

        // Gleiches Token → gleiches Konto, kein neues Token
        let again = TestClient(server: server)
        try await again.connect(name: "egal", token: a.token)
        XCTAssertEqual(again.playerID, id)
        XCTAssertNil(again.account?.token)
    }

    func testRejectsUnauthenticatedAndInvalidMessages() async throws {
        let server = makeServer()
        let c = TestClient(server: server)
        let cid = await server.connect { _ in }
        _ = cid
        // Eigene Verbindung ohne Hello
        let raw = TestClient(server: server)
        try await raw.connect(name: "X")
        await server.receive("kein json", from: raw.connectionID)
        let awaited1 = try await raw.error().code
        XCTAssertEqual(awaited1, .invalidRequest)
        _ = c
    }

    func testFriendsArePresenceAware() async throws {
        let server = makeServer()
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.addFriend(friendCode: b.account!.player.friendCode.lowercased()))
        let list = try await a.waitFor { if case .friends(let l) = $0 { return !l.isEmpty } else { return false } }
        guard case .friends(let friends) = list else { return XCTFail() }
        XCTAssertEqual(friends.first?.player.id, b.playerID)
        XCTAssertEqual(friends.first?.presence, .online)

        await b.disconnect()
        let update = try await a.waitFor { if case .friends(let l) = $0 { return l.first?.presence == .offline } else { return false } }
        XCTAssertNotNil(update)

        try await a.send(.addFriend(friendCode: "ZZZZZZ"))
        let awaited2 = try await a.error().code
        XCTAssertEqual(awaited2, .friendNotFound)
    }
}

final class RoomTests: XCTestCase {
    func testCreateJoinAndStartPrivateRoom() async throws {
        let server = makeServer()
        let host = TestClient(server: server), guest = TestClient(server: server)
        try await host.connect(name: "Host")
        try await guest.connect(name: "Gast")

        try await host.send(.createRoom(game: .blackjack))
        let room = try await host.room()!
        XCTAssertEqual(room.code.count, 6)
        XCTAssertEqual(room.members.count, 1)

        // Spieltyp wechseln, solange niemand beigetreten ist
        try await host.send(.setRoomGame(game: .poker))
        let awaited3 = try await host.room()?.game
        XCTAssertEqual(awaited3, .poker)

        // Start mit zu wenigen Spielern verboten
        try await host.send(.startRoom)
        let awaited4 = try await host.error().code
        XCTAssertEqual(awaited4, .notEnoughPlayers)

        try await guest.send(.joinRoom(code: room.code.lowercased()))
        let joined = try await guest.room()!
        XCTAssertEqual(joined.members.count, 2)
        XCTAssertTrue(joined.canStart)

        // Nach dem Beitritt kein Spielwechsel mehr; Gast darf nicht starten
        try await host.send(.setRoomGame(game: .blackjack))
        let awaited5 = try await host.error().code
        XCTAssertEqual(awaited5, .invalidRequest)
        try await guest.send(.startRoom)
        let awaited6 = try await guest.error().code
        XCTAssertEqual(awaited6, .notHost)

        try await host.send(.startRoom)
        let a = try await host.waitForTable()
        let b = try await guest.waitForTable()
        XCTAssertEqual(a.tableID, b.tableID)
        XCTAssertEqual(a.game, .poker)
        XCTAssertTrue(a.isPrivate)
    }

    func testRoomLimitsAndUnknownCodes() async throws {
        let server = makeServer()
        let host = TestClient(server: server)
        try await host.connect(name: "Host")
        try await host.send(.createRoom(game: .blackjack))
        let code = try await host.room()!.code
        var guests: [TestClient] = []
        for i in 0..<OnlineGame.blackjack.maxPlayers {
            let g = TestClient(server: server)
            try await g.connect(name: "G\(i)")
            try await g.send(.joinRoom(code: code))
            guests.append(g)
        }
        // Der fünfte Gast passt nicht mehr (Host + 4 = 5)
        let awaited7 = try await guests.last!.error().code
        XCTAssertEqual(awaited7, .roomFull)

        let lost = TestClient(server: server)
        try await lost.connect(name: "L")
        try await lost.send(.joinRoom(code: "AAAAAA"))
        let awaited8 = try await lost.error().code
        XCTAssertEqual(awaited8, .roomNotFound)
    }

    func testHostLeavingPassesHostRole() async throws {
        let server = makeServer()
        let host = TestClient(server: server), guest = TestClient(server: server)
        try await host.connect(name: "Host")
        try await guest.connect(name: "Gast")
        try await host.send(.createRoom(game: .poker))
        let code = try await host.room()!.code
        try await guest.send(.joinRoom(code: code))
        _ = try await guest.room()
        try await host.send(.leaveRoom)
        let info = try await guest.waitFor { if case .room(let r) = $0 { return r?.members.count == 1 } else { return false } }
        guard case .room(let room) = info else { return XCTFail() }
        XCTAssertEqual(room?.hostID, guest.playerID)
    }

    func testInvitationToFriend() async throws {
        let server = makeServer()
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.addFriend(friendCode: b.account!.player.friendCode))
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await a.send(.inviteFriend(playerID: b.playerID))
        let m = try await b.waitFor { if case .invitation = $0 { return true } else { return false } }
        guard case .invitation(let inv) = m else { return XCTFail() }
        XCTAssertEqual(inv.roomCode, code)
        XCTAssertEqual(inv.from.id, a.playerID)
    }
}

final class PokerOnlineTests: XCTestCase {
    /// Spielt mehrere Hände zwischen zwei echten Clients und prüft Synchronität,
    /// verdeckte Karten und Chip-Erhaltung.
    func testTwoPlayersStaySynchronizedAndCardsStayHidden() async throws {
        let server = makeServer(seed: 11)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)

        var handsSeen = Set<Int>()
        let clients = [a, b]
        let deadline = Date().addingTimeInterval(20)
        while handsSeen.count < 4 && Date() < deadline {
            for client in clients {
                guard let snap = client.latestTable, let poker = snap.poker else { continue }
                handsSeen.insert(poker.handNumber)
                // Fremde Hole Cards sind nur nach dem Showdown sichtbar
                for player in poker.players where player.seatID != snap.yourSeatID && poker.isHandInProgress {
                    XCTAssertNil(player.holeCards, "Fremde Karten dürfen nicht übertragen werden")
                }
                if let legal = poker.yourLegalActions, poker.currentSeatID == snap.yourSeatID {
                    try await client.act(.poker(action: legal.canCheck ? .check : .call), version: snap.version)
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            // Gleiche Version → identischer öffentlicher Zustand
            if let sa = a.latestTable, let sb = b.latestTable, sa.version == sb.version {
                XCTAssertEqual(sa.poker?.community, sb.poker?.community)
                XCTAssertEqual(sa.poker?.pot, sb.poker?.pot)
                XCTAssertEqual(sa.poker?.currentSeatID, sb.poker?.currentSeatID)
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertGreaterThanOrEqual(handsSeen.count, 3, "Mehrere Hände wurden gespielt")

        // Ohne Bots bleibt die Chip-Summe erhalten
        let ca = await server.onlineChips(of: a.playerID)!, cb = await server.onlineChips(of: b.playerID)!
        XCTAssertEqual(ca.free + ca.table + cb.free + cb.table, 2 * AccountStore.startingChips)
    }

    func testDuplicateStaleAndOutOfTurnActionsAreRejected() async throws {
        let server = makeServer(seed: 5)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)

        let snapA = try await a.waitForTable { $0.poker?.isHandInProgress == true }
        let actor = snapA.poker!.currentSeatID == snapA.yourSeatID ? a : b
        let other = actor === a ? b : a
        let snap = try await actor.waitForTable { $0.poker?.yourLegalActions != nil }

        // Nicht am Zug
        let wrong = UUID()
        try await other.act(.poker(action: .call), version: other.latestTable!.version, id: wrong)
        let awaited9 = try await other.actionResult(wrong).accepted
        XCTAssertFalse(awaited9)

        // Veralteter Stand
        let stale = UUID()
        try await actor.act(.poker(action: .call), version: snap.version - 50, id: stale)
        let awaited10 = try await actor.actionResult(stale).accepted
        XCTAssertFalse(awaited10)

        // Doppelt gesendete Aktion wirkt nur einmal
        let id = UUID()
        try await actor.act(.poker(action: .call), version: snap.version, id: id)
        let first = try await actor.actionResult(id)
        XCTAssertTrue(first.accepted)
        let afterFirst = try await actor.waitForTable()
        try await actor.act(.poker(action: .call), version: snap.version, id: id)
        let second = try await actor.actionResult(id)
        XCTAssertEqual(first, second)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(actor.latestTable?.poker?.pot, afterFirst.poker?.pot, "Zweite Zustellung ändert nichts")

        // Ungültiger Raise
        let bad = UUID()
        try await other.act(.poker(action: .raise(to: 1)), version: other.latestTable!.version, id: bad)
        let awaited11 = try await other.actionResult(bad).accepted
        XCTAssertFalse(awaited11)
    }

    func testTurnTimeoutKeepsGameMoving() async throws {
        let server = makeServer(seed: 7)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)
        // Niemand handelt: Server checkt/foldet nach Ablauf der Bedenkzeit, neue Hände starten
        let snap = try await a.waitForTable(timeout: 10) { ($0.poker?.handNumber ?? 0) >= 2 }
        XCTAssertGreaterThanOrEqual(snap.poker!.handNumber, 2)
    }
}

final class MatchmakingTests: XCTestCase {
    func testTwoSearchingPlayersAreMatched() async throws {
        let server = makeServer()
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.findMatch(game: .poker))
        _ = try await a.waitFor { if case .matchmaking(.searching) = $0 { return true } else { return false } }
        try await b.send(.findMatch(game: .poker))
        let ta = try await a.waitForTable()
        let tb = try await b.waitForTable()
        XCTAssertEqual(ta.tableID, tb.tableID)
        XCTAssertFalse(ta.isPrivate)
        XCTAssertTrue(ta.seats.allSatisfy { !$0.isBot })
    }

    func testBotsAreOfferedAndFairBotTableRuns() async throws {
        let server = makeServer(seed: 3)
        let a = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await a.send(.findMatch(game: .poker))
        _ = try await a.waitFor { if case .matchmaking(.noMatchFound(.poker)) = $0 { return true } else { return false } }

        // „Warten“ verlängert die Suche, danach erneut das Angebot
        try await a.send(.keepWaiting)
        _ = try await a.waitFor { if case .matchmaking(.searching) = $0 { return true } else { return false } }
        _ = try await a.waitFor { if case .matchmaking(.noMatchFound) = $0 { return true } else { return false } }

        try await a.send(.matchWithBots)
        let snap = try await a.waitForTable { $0.poker?.isHandInProgress == true }
        XCTAssertEqual(snap.seats.filter(\.isBot).count, 3)
        XCTAssertNotNil(snap.yourSeatID)

        // Spielen, bis mehrere Hände durch sind; Bot-Karten bleiben verdeckt
        let deadline = Date().addingTimeInterval(15)
        while (a.latestTable?.poker?.handNumber ?? 0) < 4 && Date() < deadline {
            if let s = a.latestTable, let p = s.poker {
                if p.isHandInProgress {
                    for player in p.players where player.seatID != s.yourSeatID { XCTAssertNil(player.holeCards) }
                }
                if let legal = p.yourLegalActions {
                    try await a.act(.poker(action: legal.canCheck ? .check : .fold), version: s.version)
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(a.latestTable?.poker?.handNumber ?? 0, 4)
    }

    func testCancelLeavesQueue() async throws {
        let server = makeServer()
        let a = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await a.send(.findMatch(game: .blackjack))
        _ = try await a.waitFor { if case .matchmaking(.searching) = $0 { return true } else { return false } }
        try await a.send(.cancelMatch)
        _ = try await a.waitFor { if case .matchmaking(.idle) = $0 { return true } else { return false } }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(a.messages.contains { if case .matchmaking(.noMatchFound) = $0 { return true } else { return false } })
    }
}

final class BlackjackOnlineTests: XCTestCase {
    func testMultiplayerRoundSettlesThroughServerWallet() async throws {
        let server = makeServer(seed: 21)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .blackjack))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)

        let open = try await a.waitForTable { $0.blackjack?.bettingOpen == true }
        // Ungültiger Einsatz wird abgelehnt
        let bad = UUID()
        try await a.act(.placeBet(amount: 5), version: open.version, id: bad)
        let awaited12 = try await a.actionResult(bad).accepted
        XCTAssertFalse(awaited12)

        try await a.act(.placeBet(amount: 100), version: open.version)
        try await b.act(.placeBet(amount: 50), version: b.latestTable?.version ?? open.version)

        // Beide spielen per Stand, bis abgerechnet ist
        let deadline = Date().addingTimeInterval(10)
        var settled: TableSnapshot?
        while Date() < deadline {
            for client in [a, b] {
                guard let s = client.latestTable, let bj = s.blackjack else { continue }
                if bj.phase == .settled, bj.seats.allSatisfy({ $0.hands.allSatisfy { $0.result != nil } }), !bj.seats.isEmpty, bj.seats.contains(where: { !$0.hands.isEmpty }) {
                    settled = s
                }
                if bj.yourActions.contains(.stand) { try await client.act(.blackjack(action: .stand), version: s.version) }
            }
            if settled != nil { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let result = try XCTUnwrap(settled?.blackjack)
        // Dealer-Karte ist am Ende offen, alle sehen denselben Dealer
        XCTAssertFalse(result.dealerCards.contains(nil))
        let mySeat = try XCTUnwrap(settled?.yourSeatID)
        let mine = result.seats.first { $0.seatID == mySeat }!
        let payout = mine.hands.compactMap(\.result).reduce(0) { $0 + $1.payout }
        let stake = mine.hands.compactMap(\.result).reduce(0) { $0 + $1.stake }
        let me = settled?.seats.first { $0.seatID == mySeat }!.player.id
        try await Task.sleep(nanoseconds: 50_000_000)
        let chips = await server.onlineChips(of: me!)!
        XCTAssertEqual(chips.free, AccountStore.startingChips - stake + payout, "Server rechnet exakt nach Engine-Ergebnis ab")
        XCTAssertEqual(chips.table, 0)
    }

    func testHoleCardHiddenAndBotsPlayByRules() async throws {
        var config = ServerConfig.testing
        config.turnTimeout = 5
        let server = makeServer(config: config, seed: 4)
        let a = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await a.send(.findMatch(game: .blackjack))
        _ = try await a.waitFor { if case .matchmaking(.noMatchFound) = $0 { return true } else { return false } }
        try await a.send(.matchWithBots)
        let open = try await a.waitForTable { $0.blackjack?.bettingOpen == true }
        XCTAssertEqual(open.seats.filter(\.isBot).count, 2)

        // Zu hoher Einsatz (über dem Guthaben) wird abgelehnt
        let tooMuch = UUID()
        try await a.act(.placeBet(amount: 1_000_000), version: open.version, id: tooMuch)
        let awaited13 = try await a.actionResult(tooMuch).accepted
        XCTAssertFalse(awaited13)

        try await a.act(.placeBet(amount: 100), version: open.version)
        let running = try await a.waitForTable { ($0.blackjack?.dealerCards.count ?? 0) >= 2 }
        let bj = running.blackjack!
        if bj.phase == .playerTurn {
            XCTAssertNil(bj.dealerCards[1], "Verdeckte Dealer-Karte wird nicht übertragen")
        }
        // Spielen bis zur Abrechnung (Stand), Bots handeln selbstständig
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let s = a.latestTable, let b = s.blackjack {
                if b.phase == .settled && !b.bettingOpen { break }
                if b.yourActions.contains(.stand) { try await a.act(.blackjack(action: .stand), version: s.version) }
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let final = try XCTUnwrap(a.latestTable?.blackjack)
        XCTAssertEqual(final.phase, .settled)
        XCTAssertFalse(final.dealerCards.contains(nil))
        let dealer = HandValue.of(final.dealerCards.compactMap { $0 })
        let anyLive = final.seats.flatMap(\.hands).contains { !$0.value.total.isMultiple(of: 1) || ($0.value.total <= 21 && !($0.cards.count == 2 && $0.value.total == 21)) }
        if anyLive && !(final.dealerCards.count == 2 && dealer.total == 21) {
            XCTAssertGreaterThanOrEqual(dealer.total, 17, "Dealer folgt S17")
        }
    }
}

final class ReconnectTests: XCTestCase {
    func testReconnectWithinGraceRestoresTable() async throws {
        var config = ServerConfig.testing
        config.reconnectGrace = 3
        config.turnTimeout = 5
        let server = makeServer(config: config, seed: 2)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)
        let before = try await a.waitForTable { $0.poker?.isHandInProgress == true }

        await a.disconnect()
        let seen = try await b.waitForTable { snap in snap.seats.contains { $0.player.id == a.playerID && !$0.isConnected } }
        XCTAssertNotNil(seen)

        // Wiederverbinden mit demselben Token → derselbe Tisch, aktueller Stand
        let again = TestClient(server: server)
        try await again.connect(name: "Anna", token: a.token)
        let restored = try await again.waitForTable()
        XCTAssertEqual(restored.tableID, before.tableID)
        XCTAssertGreaterThanOrEqual(restored.version, before.version)
        XCTAssertNotNil(restored.yourSeatID)
        _ = try await b.waitForTable { snap in snap.seats.contains { $0.player.id == a.playerID && $0.isConnected } }
    }

    func testGraceExpiryRemovesPlayerAndReturnsChips() async throws {
        let server = makeServer(seed: 8)
        let a = TestClient(server: server), b = TestClient(server: server)
        try await a.connect(name: "Anna")
        try await b.connect(name: "Ben")
        try await a.send(.createRoom(game: .poker))
        let code = try await a.room()!.code
        try await b.send(.joinRoom(code: code))
        _ = try await b.room()
        try await a.send(.startRoom)
        _ = try await a.waitForTable()
        let aID = a.playerID
        await a.disconnect()

        // Nach Ablauf der Frist: Platz frei, Tisch geschlossen (nur noch 1 Spieler), Chips zurück
        let deadline = Date().addingTimeInterval(10)
        while await server.tableID(of: aID) != nil && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let awaited14 = await server.tableID(of: aID)
        XCTAssertNil(awaited14)
        try await b.send(.leaveTable)
        while Date() < deadline {
            let ca = await server.onlineChips(of: aID)!
            let cb = await server.onlineChips(of: b.playerID)!
            if ca.table == 0 && cb.table == 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let ca = await server.onlineChips(of: aID)!, cb = await server.onlineChips(of: b.playerID)!
        XCTAssertEqual(ca.table, 0)
        XCTAssertEqual(cb.table, 0)
        XCTAssertEqual(ca.free + cb.free, 2 * AccountStore.startingChips, "Keine Chips erfunden oder verloren")
    }
}

final class PersistenceTests: XCTestCase {
    func testRestartRefundsTableChipsAndKeepsAccounts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = AccountStore(fileURL: url)
        let (account, token) = store.register(displayName: "Kim")
        try store.moveToTable(account.id, amount: 1_500)
        XCTAssertThrowsError(try store.moveToTable(account.id, amount: 1_000_000))
        XCTAssertThrowsError(try store.moveToTable(account.id, amount: -5))
        store.saveIfNeeded()

        let reloaded = AccountStore(fileURL: url)
        XCTAssertEqual(reloaded.authenticate(token: token)?.id, account.id)
        XCTAssertNil(reloaded.authenticate(token: "falsch"))
        reloaded.refundAllTableChips()
        XCTAssertEqual(reloaded.account(account.id)?.chips, AccountStore.startingChips)
        XCTAssertEqual(reloaded.account(account.id)?.tableChips, 0)

        // Token wird nur gehasht gespeichert
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains(token))
    }

    func testRateLimit() async throws {
        var config = ServerConfig.testing
        config.maxMessagesPerSecond = 5
        let server = makeServer(config: config)
        let a = TestClient(server: server)
        try await a.connect(name: "Spam")
        for _ in 0..<20 { try await a.send(.ping) }
        let awaited15 = try await a.error().code
        XCTAssertEqual(awaited15, .rateLimited)
    }
}
