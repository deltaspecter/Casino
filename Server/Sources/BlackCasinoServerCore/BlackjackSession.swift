import Foundation
import CasinoCore
import CasinoNet

/// Autoritativer Blackjack-Tisch: mehrere Plätze, ein gemeinsamer Dealer.
/// Regeln, Kartenausgabe und Abrechnung kommen aus `BlackjackTableEngine` – derselben
/// Implementierung, die die App offline verwendet.
final class BlackjackSession: TableSession {
    static let seatCount = 5
    static let rules = BlackjackRules(minBet: 10, maxBet: 1_000)

    let id: String
    let game: OnlineGame = .blackjack
    let isPrivate: Bool
    private(set) var version = 0

    private let context: TableContext
    private let engine: BlackjackTableEngine
    private var occupants: [Int: Occupant] = [:]
    /// Einsätze der nächsten Runde (bei Menschen bereits treuhänderisch vom Guthaben abgebucht).
    private var pendingBets: [Int: Int] = [:]
    /// Plätze, die in der laufenden Runde mitspielen.
    private var roundSeats: Set<Int> = []
    private var ledger = ActionLedger()
    private var timerID = 0
    private var timerPurpose: TimerPurpose?
    private var turnDeadline: Date?
    private var decisionVersion = 0
    private var bettingOpen = false
    private var showResults = false
    private var started = false

    private enum TimerPurpose { case bettingClosed, turnTimeout(seat: Int), botAction(seat: Int), nextRound }

    init(id: String, isPrivate: Bool, context: TableContext) {
        self.id = id
        self.isPrivate = isPrivate
        self.context = context
        engine = BlackjackTableEngine(rules: Self.rules, random: context.cardRandom)
    }

    // MARK: - Plätze

    var hasFreeSeat: Bool { occupants.count < Self.seatCount }
    var humanIDs: [String] { occupants.values.filter { !$0.isBot }.map(\.player.id) }
    var hasConnectedHuman: Bool { occupants.values.contains { !$0.isBot && $0.isConnected && !$0.isLeaving } }
    private var isRoundRunning: Bool { engine.phase == .playerTurn || engine.phase == .dealerTurn }

    private func slot(of playerID: String) -> Int? { occupants.first { $0.value.player.id == playerID }?.key }

    func addHuman(_ player: PlayerInfo) throws {
        guard slot(of: player.id) == nil else { return }
        guard let slot = (0..<Self.seatCount).first(where: { occupants[$0] == nil }) else { throw TableJoinError.full }
        occupants[slot] = Occupant(player: player, isBot: false, botStyle: nil)
        bump()
    }

    func addBot() {
        guard let slot = (0..<Self.seatCount).first(where: { occupants[$0] == nil }) else { return }
        let used = Set(occupants.values.map(\.player.displayName))
        occupants[slot] = Occupant(player: BotNames.make(random: context.botRandom, avoiding: used), isBot: true, botStyle: nil)
        bump()
    }

    func start() {
        guard !started else { return }
        started = true
        openBetting()
    }

    func setConnected(_ playerID: String, _ connected: Bool) {
        guard let slot = slot(of: playerID) else { return }
        occupants[slot]?.isConnected = connected
        bump()
    }

    /// Verlassen: Ein offener Einsatz vor Rundenbeginn wird zurückgebucht. In einer laufenden
    /// Runde bleiben alle Hände stehen; die Runde wird regulär abgerechnet, danach ist der Platz frei.
    func remove(_ playerID: String) {
        guard let slot = slot(of: playerID) else { return }
        if roundSeats.contains(slot) && isRoundRunning {
            occupants[slot]?.isLeaving = true
            if engine.currentSeatID == slot {
                engine.standAll(seat: slot)
                afterEngineChange()
            } else {
                bump()
            }
            return
        }
        if let bet = pendingBets.removeValue(forKey: slot) {
            context.wallet.releaseFromTable(playerID, stake: bet, payout: bet)
            context.touchedAccounts.insert(playerID)
        }
        occupants[slot] = nil
        context.departed.append(playerID)
        bump()
        if bettingOpen { maybeStartRound(force: false) }
    }

    // MARK: - Aktionen

    func handle(_ request: TableActionRequest, from playerID: String) -> ActionResult {
        if let previous = ledger.result(for: request.actionID) { return previous }
        let result = process(request, from: playerID)
        ledger.record(result)
        return result
    }

    private func process(_ request: TableActionRequest, from playerID: String) -> ActionResult {
        func reject(_ reason: String) -> ActionResult { ActionResult(actionID: request.actionID, accepted: false, reason: reason) }
        func accept() -> ActionResult { ActionResult(actionID: request.actionID, accepted: true, reason: nil) }
        guard let slot = slot(of: playerID), occupants[slot]?.isLeaving == false else { return reject("Du sitzt nicht an diesem Tisch.") }

        switch request.action {
        case .placeBet(let amount):
            guard bettingOpen else { return reject("Einsätze sind gerade geschlossen.") }
            guard pendingBets[slot] == nil else { return reject("Du hast bereits gesetzt.") }
            guard amount >= Self.rules.minBet && amount <= Self.rules.maxBet else {
                return reject("Einsatz muss zwischen \(Self.rules.minBet) und \(Self.rules.maxBet) liegen.")
            }
            guard (try? context.wallet.moveToTable(playerID, amount: amount)) != nil else { return reject("Nicht genug Online-Chips.") }
            context.touchedAccounts.insert(playerID)
            pendingBets[slot] = amount
            bump()
            maybeStartRound(force: false)
            return accept()

        case .blackjack(let action):
            guard engine.phase == .playerTurn, engine.currentSeatID == slot else { return reject("Du bist nicht am Zug.") }
            guard request.stateVersion >= decisionVersion else { return reject("Spielstand veraltet – bitte erneut versuchen.") }
            guard engine.availableActions(forSeat: slot).contains(action) else { return reject("Ungültige Aktion.") }
            let extra = engine.additionalStake(for: action, seat: slot)
            if extra > 0 {
                guard (try? context.wallet.moveToTable(playerID, amount: extra)) != nil else {
                    return reject("Nicht genug Online-Chips für \(action == .double ? "Double" : "Split").")
                }
                context.touchedAccounts.insert(playerID)
            }
            do {
                try engine.perform(action, seat: slot)
            } catch {
                if extra > 0 { context.wallet.releaseFromTable(playerID, stake: extra, payout: extra) }
                return reject("Ungültige Aktion.")
            }
            afterEngineChange()
            return accept()

        case .poker, .rebuy:
            return reject("Aktion gehört nicht zu Blackjack.")
        }
    }

    // MARK: - Ablauf

    private func openBetting() {
        // Leere Plätze aufräumen
        for slot in occupants.keys.sorted() where occupants[slot]!.isLeaving {
            context.departed.append(occupants[slot]!.player.id)
            occupants[slot] = nil
        }
        roundSeats = []
        showResults = false
        bettingOpen = true
        turnDeadline = nil
        timerPurpose = nil
        // Bots setzen sofort einen kleinen, zufällig gewählten Einsatz (ihr Guthaben ist virtuell).
        for (slot, o) in occupants where o.isBot {
            pendingBets[slot] = Self.rules.minBet * (1 + context.botRandom.uniform(5))
        }
        bump()
        decisionVersion = version
    }

    /// Startet die Runde, wenn alle verbundenen Menschen gesetzt haben – oder nach Ablauf der Setzzeit.
    private func maybeStartRound(force: Bool) {
        guard bettingOpen else { return }
        let humanSlots = occupants.filter { !$0.value.isBot && $0.value.isConnected && !$0.value.isLeaving }.map(\.key)
        let humanBets = humanSlots.filter { pendingBets[$0] != nil }
        guard !humanBets.isEmpty else {
            // Ohne menschlichen Einsatz keine Runde; offene Bot-Einsätze bleiben stehen.
            turnDeadline = nil
            return
        }
        if force || humanBets.count == humanSlots.count {
            startRound()
        } else if turnDeadline == nil {
            turnDeadline = context.now().addingTimeInterval(context.config.bettingWindow)
            schedule(.bettingClosed, after: context.config.bettingWindow)
            bump()
        }
    }

    private func startRound() {
        let bets = pendingBets.keys.sorted().compactMap { slot -> (seatID: Int, bet: Int)? in
            guard occupants[slot] != nil else { return nil }
            return (seatID: slot, bet: pendingBets[slot]!)
        }
        guard !bets.isEmpty else { return }
        bettingOpen = false
        roundSeats = Set(bets.map(\.seatID))
        pendingBets = [:]
        turnDeadline = nil
        do {
            try engine.startRound(bets: bets)
        } catch {
            // Sollte nie passieren (Einsätze wurden validiert) – dann alles zurückbuchen.
            for bet in bets {
                if let o = occupants[bet.seatID], !o.isBot {
                    context.wallet.releaseFromTable(o.player.id, stake: bet.bet, payout: bet.bet)
                    context.touchedAccounts.insert(o.player.id)
                }
            }
            openBetting()
            return
        }
        afterEngineChange()
    }

    private func afterEngineChange() {
        bump()
        switch engine.phase {
        case .playerTurn:
            guard let slot = engine.currentSeatID else { return }
            decisionVersion = version
            if occupants[slot]?.isBot == true {
                turnDeadline = nil
                schedule(.botAction(seat: slot), after: Double.random(in: context.config.botThinkTime))
            } else if occupants[slot]?.isLeaving == true || occupants[slot] == nil {
                turnDeadline = nil
                schedule(.turnTimeout(seat: slot), after: 0)
            } else {
                turnDeadline = context.now().addingTimeInterval(context.config.turnTimeout)
                schedule(.turnTimeout(seat: slot), after: context.config.turnTimeout)
            }
        case .settled:
            settle()
        case .betting, .dealerTurn:
            break
        }
    }

    /// Abrechnung: Auszahlungen gehen auf das Online-Guthaben – auch wenn der Spieler gegangen ist.
    private func settle() {
        turnDeadline = nil
        showResults = true
        for seat in engine.seats {
            guard let o = occupants[seat.seatID], !o.isBot else { continue }
            let stake = seat.results.reduce(0) { $0 + $1.stake }
            let payout = seat.results.reduce(0) { $0 + $1.payout }
            context.wallet.releaseFromTable(o.player.id, stake: stake, payout: payout)
            context.touchedAccounts.insert(o.player.id)
        }
        schedule(.nextRound, after: context.config.resultPause)
    }

    private func schedule(_ purpose: TimerPurpose, after delay: TimeInterval) {
        timerID += 1
        timerPurpose = purpose
        context.scheduleTimer(timerID, delay)
    }

    func timerFired(_ id: Int) {
        guard id == timerID, let purpose = timerPurpose else { return }
        timerPurpose = nil
        switch purpose {
        case .bettingClosed:
            maybeStartRound(force: true)
        case .turnTimeout(let slot):
            guard engine.currentSeatID == slot else { return }
            engine.standAll(seat: slot)
            afterEngineChange()
        case .botAction(let slot):
            // Der Bot sieht nur seine Hand und die offene Dealer-Karte.
            guard engine.currentSeatID == slot, let hand = engine.currentHand, let up = engine.dealerCards.first else { return }
            let action = BlackjackBot.decide(hand: hand, dealerUpcard: up, available: engine.availableActions(forSeat: slot))
            if (try? engine.perform(action, seat: slot)) == nil { engine.standAll(seat: slot) }
            afterEngineChange()
        case .nextRound:
            openBetting()
        }
    }

    private func bump() { version += 1 }

    // MARK: - Sicht pro Spieler

    func snapshot(for playerID: String?) -> TableSnapshot {
        let mySlot = playerID.flatMap { slot(of: $0) }
        let seats = occupants.keys.sorted().map { slot -> TableSeat in
            let o = occupants[slot]!
            return TableSeat(seatID: slot, player: o.player, isBot: o.isBot, botStyle: o.isBot ? "Grundstrategie" : nil,
                             isConnected: o.isConnected && !o.isLeaving)
        }
        let roundVisible = isRoundRunning || showResults
        let seatSnapshots = occupants.keys.sorted().map { slot -> BlackjackSeatSnapshot in
            let hands: [BlackjackHandSnapshot]
            if roundVisible, let seat = engine.seat(slot) {
                hands = seat.hands.map { hand in
                    BlackjackHandSnapshot(id: hand.id, cards: hand.cards, bet: hand.bet, isDoubled: hand.isDoubled,
                                          result: showResults ? seat.results.first { $0.handID == hand.id } : nil)
                }
            } else {
                hands = []
            }
            return BlackjackSeatSnapshot(seatID: slot, pendingBet: pendingBets[slot], hands: hands)
        }
        // Verdeckte Dealer-Karte wird als `nil` übertragen, bis sie aufgedeckt ist.
        let dealer: [Card?] = roundVisible
            ? engine.dealerCards.enumerated().map { i, card in (i == 1 && !engine.isHoleCardRevealed) ? nil : card }
            : []
        let isMyTurn = mySlot != nil && engine.currentSeatID == mySlot
        let bj = BlackjackTableSnapshot(
            phase: bettingOpen ? .betting : engine.phase, bettingOpen: bettingOpen, dealerCards: dealer,
            seats: seatSnapshots, currentSeatID: isRoundRunning ? engine.currentSeatID : nil,
            currentHandID: isRoundRunning ? engine.currentHand?.id : nil,
            minBet: Self.rules.minBet, maxBet: Self.rules.maxBet,
            yourActions: isMyTurn ? engine.availableActions(forSeat: mySlot!).sorted { $0.rawValue < $1.rawValue } : [],
            yourAdditionalStake: isMyTurn ? (engine.currentHand?.bet ?? 0) : 0)
        return TableSnapshot(tableID: id, game: .blackjack, version: version, isPrivate: isPrivate, yourSeatID: mySlot,
                             seats: seats, turnDeadline: turnDeadline, blackjack: bj, poker: nil)
    }
}
