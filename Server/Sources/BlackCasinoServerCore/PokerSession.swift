import Foundation
import CasinoCore
import CasinoNet

/// Autoritativer Texas-Hold'em-Tisch. Deck, Kartenverteilung, Einsätze, Pot, Reihenfolge,
/// Turn, River und Gewinner bestimmt ausschließlich die `HoldemEngine` auf dem Server.
/// Clients senden nur Absichten (Fold/Check/Call/Raise) und erhalten den resultierenden Zustand.
final class PokerSession: TableSession {
    static let seatCount = 6
    static let smallBlind = 10
    static let bigBlind = 20
    static let buyIn = 2_000
    static let minBuyIn = 400

    let id: String
    let game: OnlineGame = .poker
    let isPrivate: Bool
    private(set) var version = 0

    private let context: TableContext
    private let engine: HoldemEngine
    private var occupants: [Int: Occupant] = [:]
    /// Stack für Plätze, die während einer laufenden Hand dazukommen oder nachkaufen.
    private var pendingStacks: [Int: Int] = [:]
    /// Chips, die dieser Tisch für jeden Menschen treuhänderisch hält (= sein Stack nach der letzten Hand).
    private var escrowed: [String: Int] = [:]
    private var ledger = ActionLedger()
    private var timerID = 0
    private var timerPurpose: TimerPurpose?
    private var turnDeadline: Date?
    /// Version, ab der die aktuelle Entscheidung gilt (ältere Client-Stände werden abgelehnt).
    private var decisionVersion = 0
    private var started = false

    private enum TimerPurpose { case turnTimeout(seat: Int), botAction(seat: Int), nextHand }

    init(id: String, isPrivate: Bool, context: TableContext) {
        self.id = id
        self.isPrivate = isPrivate
        self.context = context
        let empty = (0..<Self.seatCount).map { PokerSeat(id: $0, name: "", isHuman: false, style: nil, stack: 0) }
        engine = HoldemEngine(seats: empty, smallBlind: Self.smallBlind, bigBlind: Self.bigBlind, random: context.cardRandom)
    }

    // MARK: - Plätze

    var hasFreeSeat: Bool { occupants.count < Self.seatCount }
    var humanIDs: [String] { occupants.values.filter { !$0.isBot }.map(\.player.id) }
    var hasConnectedHuman: Bool { occupants.values.contains { !$0.isBot && $0.isConnected && !$0.isLeaving } }

    private func slot(of playerID: String) -> Int? {
        occupants.first { $0.value.player.id == playerID }?.key
    }

    private func freeSlot() -> Int? {
        (0..<Self.seatCount).first { occupants[$0] == nil }
    }

    func addHuman(_ player: PlayerInfo) throws {
        guard slot(of: player.id) == nil else { return }
        guard let slot = freeSlot() else { throw TableJoinError.full }
        let available = context.wallet.account(player.id)?.chips ?? 0
        let buyIn = min(Self.buyIn, available)
        guard buyIn >= Self.minBuyIn else { throw TableJoinError.insufficientChips }
        try context.wallet.moveToTable(player.id, amount: buyIn)
        escrowed[player.id, default: 0] += buyIn
        context.touchedAccounts.insert(player.id)
        occupants[slot] = Occupant(player: player, isBot: false, botStyle: nil)
        seatStack(slot, buyIn, player: player, isHuman: true, style: nil)
        bump()
        if started { startHandIfPossible() }
    }

    func addBot() {
        guard let slot = freeSlot() else { return }
        let used = Set(occupants.values.map(\.player.displayName))
        let player = BotNames.make(random: context.botRandom, avoiding: used)
        let style = context.botRandom.pick([PokerStyle.rock, .shark, .maniac]) ?? .shark
        occupants[slot] = Occupant(player: player, isBot: true, botStyle: style)
        seatStack(slot, Self.buyIn, player: player, isHuman: false, style: style)
        bump()
    }

    /// Setzt den Stack sofort (zwischen Händen) oder merkt ihn für die nächste Hand vor.
    private func seatStack(_ slot: Int, _ stack: Int, player: PlayerInfo, isHuman: Bool, style: PokerStyle?) {
        if engine.isHandInProgress {
            pendingStacks[slot] = (pendingStacks[slot] ?? 0) + stack
        } else {
            try? engine.replaceSeat(at: slot, with: PokerSeat(id: slot, name: player.displayName, isHuman: isHuman,
                                                              style: style, stack: engine.seats[slot].stack + stack))
        }
    }

    func start() {
        started = true
        startHandIfPossible()
    }

    func setConnected(_ playerID: String, _ connected: Bool) {
        guard let slot = slot(of: playerID) else { return }
        occupants[slot]?.isConnected = connected
        bump()
    }

    /// Verlassen: Ist der Spieler gerade am Zug, foldet er. Sein Platz wird nach der Hand frei
    /// und der verbleibende Stack seinem Online-Guthaben gutgeschrieben.
    func remove(_ playerID: String) {
        guard let slot = slot(of: playerID) else { return }
        occupants[slot]?.isLeaving = true
        if engine.isHandInProgress {
            if engine.currentIndex == slot { apply(.fold, slot: slot) }
            bump()
        } else {
            vacate(slot)
            bump()
            startHandIfPossible()
        }
    }

    private func vacate(_ slot: Int) {
        guard let occupant = occupants[slot] else { return }
        let stack = engine.seats[slot].stack + (pendingStacks[slot] ?? 0)
        if !occupant.isBot {
            let escrow = escrowed.removeValue(forKey: occupant.player.id) ?? 0
            context.wallet.releaseFromTable(occupant.player.id, stake: escrow, payout: stack)
            context.touchedAccounts.insert(occupant.player.id)
            context.departed.append(occupant.player.id)
        }
        occupants[slot] = nil
        pendingStacks[slot] = nil
        try? engine.replaceSeat(at: slot, with: PokerSeat(id: slot, name: "", isHuman: false, style: nil, stack: 0))
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
        guard let slot = slot(of: playerID), occupants[slot]?.isLeaving == false else { return reject("Du sitzt nicht an diesem Tisch.") }

        switch request.action {
        case .rebuy:
            let stack = engine.seats[slot].stack + (pendingStacks[slot] ?? 0)
            guard stack == 0 else { return reject("Nachkaufen ist nur mit leerem Stack möglich.") }
            let available = context.wallet.account(playerID)?.chips ?? 0
            let amount = min(Self.buyIn, available)
            guard amount >= Self.minBuyIn, (try? context.wallet.moveToTable(playerID, amount: amount)) != nil else {
                return reject("Nicht genug Online-Chips.")
            }
            escrowed[playerID, default: 0] += amount
            context.touchedAccounts.insert(playerID)
            seatStack(slot, amount, player: occupants[slot]!.player, isHuman: true, style: nil)
            bump()
            startHandIfPossible()
            return ActionResult(actionID: request.actionID, accepted: true, reason: nil)

        case .poker(let action):
            guard engine.isHandInProgress, engine.currentIndex == slot else { return reject("Du bist nicht am Zug.") }
            guard request.stateVersion >= decisionVersion else { return reject("Spielstand veraltet – bitte erneut versuchen.") }
            guard apply(action, slot: slot) else { return reject("Ungültige Aktion.") }
            return ActionResult(actionID: request.actionID, accepted: true, reason: nil)

        case .placeBet, .blackjack:
            return reject("Aktion gehört nicht zu Poker.")
        }
    }

    @discardableResult
    private func apply(_ action: PokerAction, slot: Int) -> Bool {
        guard (try? engine.apply(action, forSeatAt: slot)) != nil else { return false }
        afterEngineChange()
        return true
    }

    // MARK: - Spielablauf

    private func startHandIfPossible() {
        guard started, !engine.isHandInProgress, !isNextHandTimer else { return }
        // Wartende Änderungen übernehmen
        for slot in occupants.keys.sorted() where occupants[slot]!.isLeaving { vacate(slot) }
        for (slot, extra) in pendingStacks {
            guard let occupant = occupants[slot] else { continue }
            try? engine.replaceSeat(at: slot, with: PokerSeat(id: slot, name: occupant.player.displayName, isHuman: !occupant.isBot,
                                                              style: occupant.botStyle, stack: engine.seats[slot].stack + extra))
        }
        pendingStacks = [:]
        // Bots ohne Chips gehen; an Bot-Tischen nimmt ein neuer Bot Platz
        for slot in occupants.keys.sorted() where occupants[slot]!.isBot && engine.seats[slot].stack == 0 {
            occupants[slot] = nil
            try? engine.replaceSeat(at: slot, with: PokerSeat(id: slot, name: "", isHuman: false, style: nil, stack: 0))
            if hasConnectedHuman { addBot() }
        }

        let playable = engine.seats.filter { $0.stack > 0 }.count
        guard hasConnectedHuman, playable >= 2 else {
            timerPurpose = nil
            turnDeadline = nil
            bump()
            return
        }
        do {
            try engine.startHand()
            afterEngineChange()
        } catch {
            bump()
        }
    }

    private var isNextHandTimer: Bool {
        if case .nextHand = timerPurpose { return true }
        return false
    }

    /// Nach jeder Änderung: Zustand veröffentlichen und den nächsten Schritt planen.
    private func afterEngineChange() {
        bump()
        if engine.isHandInProgress, let slot = engine.currentIndex {
            decisionVersion = version
            if occupants[slot]?.isLeaving == true || occupants[slot] == nil {
                // Spieler hat den Tisch verlassen: sofort folden
                turnDeadline = nil
                schedule(.turnTimeout(seat: slot), after: 0)
            } else if occupants[slot]?.isBot == true {
                turnDeadline = nil
                schedule(.botAction(seat: slot), after: Double.random(in: context.config.botThinkTime))
            } else {
                turnDeadline = context.now().addingTimeInterval(context.config.turnTimeout)
                schedule(.turnTimeout(seat: slot), after: context.config.turnTimeout)
            }
        } else if !engine.isHandInProgress {
            handFinished()
        }
    }

    private func handFinished() {
        turnDeadline = nil
        // Gewinne und Verluste der Hand im Treuhandbetrag nachführen
        for (slot, occupant) in occupants where !occupant.isBot {
            let stack = engine.seats[slot].stack + (pendingStacks[slot] ?? 0)
            let id = occupant.player.id
            context.wallet.adjustTableChips(id, by: stack - (escrowed[id] ?? 0))
            escrowed[id] = stack
            context.touchedAccounts.insert(id)
        }
        schedule(.nextHand, after: context.config.resultPause)
    }

    private func schedule(_ purpose: TimerPurpose, after delay: TimeInterval) {
        timerID += 1
        timerPurpose = purpose
        context.scheduleTimer(timerID, delay)
    }

    func timerFired(_ id: Int) {
        guard id == timerID, let purpose = timerPurpose else { return } // veralteter Timer
        timerPurpose = nil
        switch purpose {
        case .turnTimeout(let slot):
            guard engine.currentIndex == slot, let legal = engine.legalActions(forSeatAt: slot) else { return }
            // Zeit abgelaufen: Check, wenn möglich, sonst Fold. Wer gegangen ist, foldet.
            let leaving = occupants[slot]?.isLeaving ?? true
            apply(legal.canCheck && !leaving ? .check : .fold, slot: slot)
        case .botAction(let slot):
            guard engine.currentIndex == slot, let style = occupants[slot]?.botStyle else { return }
            // Der Bot sieht nur, was jeder Spieler an seinem Platz sehen würde.
            let context = PokerAIContext(engine: engine, seatIndex: slot)
            let action = PokerAI.decide(context: context, style: style, random: self.context.botRandom)
            if !apply(action, slot: slot) {
                let legal = engine.legalActions(forSeatAt: slot)
                apply(legal?.canCheck == true ? .check : .fold, slot: slot)
            }
        case .nextHand:
            startHandIfPossible()
        }
    }

    private func bump() { version += 1 }

    // MARK: - Sicht pro Spieler

    func snapshot(for playerID: String?) -> TableSnapshot {
        let mySlot = playerID.flatMap { slot(of: $0) }
        let revealed = Set(engine.isHandInProgress ? [] : engine.lastShowdown.map(\.seatID))
        let seats = occupants.keys.sorted().map { slot -> TableSeat in
            let o = occupants[slot]!
            return TableSeat(seatID: slot, player: o.player, isBot: o.isBot, botStyle: o.botStyle?.title,
                             isConnected: o.isConnected && !o.isLeaving)
        }
        let players = occupants.keys.sorted().map { slot -> PokerPlayerSnapshot in
            let s = engine.seats[slot]
            let visible = slot == mySlot || revealed.contains(slot)
            return PokerPlayerSnapshot(
                seatID: slot, stack: s.stack + (pendingStacks[slot] ?? 0), streetBet: s.streetBet,
                hasFolded: s.hasFolded, isAllIn: s.isAllIn, isSittingOut: s.isSittingOut || s.holeCards.isEmpty,
                hasCards: !s.holeCards.isEmpty && !s.hasFolded,
                holeCards: visible && !s.holeCards.isEmpty ? s.holeCards : nil,
                lastAction: s.lastAction)
        }
        let poker = PokerTableSnapshot(
            handNumber: engine.handNumber, isHandInProgress: engine.isHandInProgress, street: engine.street,
            community: engine.community, pot: engine.pot, currentBet: engine.currentBet,
            smallBlind: Self.smallBlind, bigBlind: Self.bigBlind,
            buttonSeatID: engine.handNumber > 0 ? engine.buttonIndex : nil,
            currentSeatID: engine.currentIndex,
            players: players,
            showdown: engine.isHandInProgress ? [] : engine.lastShowdown.map { ShowdownSnapshot(seatID: $0.seatID, handName: $0.hand.name) },
            awards: engine.isHandInProgress ? [] : engine.lastAwards,
            yourLegalActions: mySlot.flatMap { engine.legalActions(forSeatAt: $0) })
        return TableSnapshot(tableID: id, game: .poker, version: version, isPrivate: isPrivate, yourSeatID: mySlot,
                             seats: seats, turnDeadline: turnDeadline, blackjack: nil, poker: poker)
    }
}
