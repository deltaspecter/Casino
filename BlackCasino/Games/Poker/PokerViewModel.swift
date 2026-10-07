import SwiftUI
import Observation
import CasinoCore

@MainActor
@Observable
final class PokerViewModel {
    enum Stage: Equatable { case setup, playing, handOver, busted }

    struct TableOption: Identifiable, Equatable {
        let id: String
        let name: String
        let smallBlind: Int
        let bigBlind: Int
        let minBuyIn: Int
        let maxBuyIn: Int
    }

    static let tables: [TableOption] = [
        TableOption(id: "lounge", name: "Lounge", smallBlind: 10, bigBlind: 20, minBuyIn: 400, maxBuyIn: 2_000),
        TableOption(id: "highstakes", name: "High Stakes", smallBlind: 50, bigBlind: 100, minBuyIn: 2_000, maxBuyIn: 10_000),
        TableOption(id: "vip", name: "VIP Salon", smallBlind: 250, bigBlind: 500, minBuyIn: 10_000, maxBuyIn: 50_000)
    ]

    private static let names = ["Viktor", "Lena", "Marco", "Sofia", "Jonas", "Ava", "Elias", "Mila",
                                "Noah", "Clara", "Leon", "Ida", "Felix", "Nora", "Theo", "Lia"]

    static let humanSeatID = 0

    // Setup
    var selectedTable: TableOption = tables[0]
    var opponentCount = 4
    var buyIn = 1_000

    // Tischzustand (Momentaufnahme für die Anzeige)
    private(set) var stage: Stage = .setup
    private(set) var seats: [PokerSeat] = []
    private(set) var community: [Card] = []
    private(set) var pot = 0
    private(set) var buttonSeatID: Int?
    private(set) var thinkingSeatID: Int?
    private(set) var legal: PokerLegalActions?
    private(set) var lastActions: [Int: String] = [:]
    private(set) var revealedSeats: Set<Int> = []
    private(set) var showdownHands: [Int: String] = [:]
    private(set) var resultText: String?
    private(set) var humanWonLastHand = false
    var raiseTarget: Double = 0
    var anchors: [String: CGPoint] = [:]

    @ObservationIgnored let table: PokerTable
    @ObservationIgnored private var engine: HoldemEngine?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var handWasRecorded = true

    init(app: AppModel) {
        self.app = app
        table = PokerTable(reducedEffects: app.profile.settings.reducedMotion)
        selectedTable = Self.tables.last { $0.minBuyIn <= app.chips } ?? Self.tables[0]
        buyIn = clampedBuyIn(selectedTable.maxBuyIn / 2)
    }

    // MARK: - Abfragen

    var human: PokerSeat? { seats.first { $0.id == Self.humanSeatID } }
    var isHumanTurn: Bool { legal != nil }
    var bigBlind: Int { engine?.bigBlind ?? selectedTable.bigBlind }

    /// Aktuelle beste Hand des Spielers (nur Anzeige).
    var humanHandName: String? {
        guard let human, human.holeCards.count == 2, community.count >= 3 else { return nil }
        return HandEvaluator.bestHand(human.holeCards + community).name
    }

    func clampedBuyIn(_ value: Int) -> Int {
        let maxAffordable = min(selectedTable.maxBuyIn, app?.chips ?? 0)
        let step = selectedTable.bigBlind
        let v = min(max(value, selectedTable.minBuyIn), max(selectedTable.minBuyIn, maxAffordable))
        return (v / step) * step
    }

    var canAffordSelectedTable: Bool { (app?.chips ?? 0) >= selectedTable.minBuyIn }

    // MARK: - Tisch betreten / verlassen

    func sitDown() async {
        guard let app, stage == .setup else { return }
        let amount = clampedBuyIn(buyIn)
        guard amount >= selectedTable.minBuyIn, app.moveToTable(amount) else { return }

        var seats = [PokerSeat(id: Self.humanSeatID, name: app.profile.displayName, isHuman: true, style: nil, stack: amount)]
        var usedNames: Set<String> = []
        for id in 1...opponentCount {
            seats.append(makeOpponent(id: id, avoiding: &usedNames))
        }
        engine = HoldemEngine(seats: seats, smallBlind: selectedTable.smallBlind, bigBlind: selectedTable.bigBlind,
                              random: app.random)
        table.configureSeats(ids: seats.map(\.id), opponents: opponentCount)
        self.seats = seats
        stage = .playing
        await nextHand()
    }

    private func makeOpponent(id: Int, avoiding used: inout Set<String>) -> PokerSeat {
        guard let app else { return PokerSeat(id: id, name: "KI \(id)", isHuman: false, style: .shark, stack: 1_000) }
        let available = Self.names.filter { !used.contains($0) }
        let name = app.random.pick(available) ?? "KI \(id)"
        used.insert(name)
        let style = app.random.pick(PokerStyle.allCases) ?? .shark
        let steps = (selectedTable.maxBuyIn - selectedTable.minBuyIn) / selectedTable.bigBlind
        let stack = selectedTable.minBuyIn + app.random.uniform(steps + 1) * selectedTable.bigBlind
        return PokerSeat(id: id, name: name, isHuman: false, style: style, stack: stack)
    }

    /// Verlassen: Restliche Chips gehen zurück aufs Konto. Ein laufender Einsatz gilt als gefoldet.
    func leave() {
        guard let app, let engine else { return }
        isRunning = false
        let stack = engine.seats.first { $0.id == Self.humanSeatID }?.stack ?? 0
        if engine.isHandInProgress && !handWasRecorded {
            let contributed = engine.seats.first { $0.id == Self.humanSeatID }?.handContribution ?? 0
            app.record(.pokerHand(contributed: contributed, won: 0))
            handWasRecorded = true
        }
        app.releaseFromTable(stake: app.profile.tableEscrow, payout: stack)
        self.engine = nil
        stage = .setup
    }

    func topUp(_ amount: Int) {
        guard let app, let engine, !engine.isHandInProgress, amount > 0,
              let index = engine.seats.firstIndex(where: { $0.id == Self.humanSeatID }) else { return }
        guard app.moveToTable(amount) else { return }
        try? engine.setStack(engine.seats[index].stack + amount, forSeatAt: index)
        seats = engine.seats
        if stage == .busted { stage = .handOver }
    }

    // MARK: - Spielablauf

    func nextHand() async {
        guard let app, let engine, !engine.isHandInProgress, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Ausgeschiedene KI-Gegner werden durch neue ersetzt
        var used = Set(engine.seats.map(\.name))
        for (i, seat) in engine.seats.enumerated() where !seat.isHuman && seat.stack == 0 {
            let fresh = makeOpponent(id: seat.id, avoiding: &used)
            try? engine.replaceSeat(at: i, with: fresh)
            app.show(Toast(icon: "person.fill.badge.plus", title: "\(fresh.name) nimmt Platz",
                           subtitle: "Spielstil: \(fresh.style?.title ?? "")", tint: Theme.gold))
        }
        guard (engine.seats.first { $0.id == Self.humanSeatID }?.stack ?? 0) > 0 else {
            stage = .busted
            return
        }

        stage = .playing
        resultText = nil
        humanWonLastHand = false
        revealedSeats = []
        showdownHands = [:]
        lastActions = [:]
        community = []
        legal = nil
        await table.clear()

        do {
            let events = try engine.startHand()
            handWasRecorded = false
            seats = engine.seats
            await play(events)
            await runOpponents()
        } catch {
            app.show(Toast(icon: "exclamationmark.triangle", title: "Hand konnte nicht starten", subtitle: nil, tint: Theme.red))
        }
    }

    /// Lässt die KI-Gegner handeln, bis der Spieler dran ist oder die Hand endet.
    private func runOpponents() async {
        guard let app else { return }
        while let engine = self.engine, engine.isHandInProgress, let index = engine.currentIndex {
            let seat = engine.seats[index]
            if seat.isHuman {
                thinkingSeatID = nil
                legal = engine.legalActions(forSeatAt: index)
                if let legal { raiseTarget = Double(legal.minRaiseTo) }
                return
            }
            thinkingSeatID = seat.id
            // Natürliche Bedenkzeit (rein optisch)
            await sceneDelay(0.55 + app.random.unitDouble() * 0.8)
            guard self.engine === engine, engine.currentIndex == index else { return }

            let context = PokerAIContext(engine: engine, seatIndex: index)
            let style = seat.style ?? .shark
            let random = app.random
            let action = await Task.detached(priority: .userInitiated) {
                PokerAI.decide(context: context, style: style, random: random)
            }.value
            guard self.engine === engine, engine.currentIndex == index else { return }

            let events: [PokerEvent]
            if let e = try? engine.apply(action, forSeatAt: index) {
                events = e
            } else {
                // Sicherheitsnetz: nie hängen bleiben
                let fallback: PokerAction = engine.legalActions(forSeatAt: index)?.canCheck == true ? .check : .fold
                events = (try? engine.apply(fallback, forSeatAt: index)) ?? []
            }
            thinkingSeatID = nil
            await play(events)
        }
        if let engine = self.engine, !engine.isHandInProgress { finishHand(engine) }
    }

    func act(_ action: PokerAction) async {
        guard let engine, legal != nil, let index = engine.currentIndex, engine.seats[index].isHuman else { return }
        legal = nil
        Haptics.tap()
        do {
            let events = try engine.apply(action, forSeatAt: index)
            await play(events)
        } catch {
            legal = engine.legalActions(forSeatAt: index)
            return
        }
        await runOpponents()
    }

    func confirmRaise() async {
        guard let legal else { return }
        let target = Int(raiseTarget.rounded())
        if target >= legal.maxRaiseTo { await act(.allIn) } else { await act(.raise(to: max(target, legal.minRaiseTo))) }
    }

    /// Setzt den Regler auf einen Anteil des Pots.
    func setRaise(potFraction: Double) {
        guard let legal, let engine else { return }
        let toCall = legal.callAmount
        let target = engine.currentBet + Int(Double(engine.pot + toCall) * potFraction)
        raiseTarget = Double(min(max(target, legal.minRaiseTo), legal.maxRaiseTo))
        Haptics.selection()
    }

    private func finishHand(_ engine: HoldemEngine) {
        guard !handWasRecorded, let app, let human = engine.seats.first(where: { $0.id == Self.humanSeatID }) else { return }
        handWasRecorded = true
        seats = engine.seats
        pot = 0
        let won = engine.lastAwards.filter { $0.seatID == Self.humanSeatID }.reduce(0) { $0 + $1.amount }
        if !human.isSittingOut {
            app.record(.pokerHand(contributed: human.handContribution, won: won))
        }
        app.setTableEscrow(human.stack)
        humanWonLastHand = won > 0

        var lines: [String] = []
        for award in engine.lastAwards {
            let name = engine.seats.first { $0.id == award.seatID }?.name ?? "?"
            let hand = award.handName.map { " mit \($0)" } ?? ""
            lines.append("\(award.seatID == Self.humanSeatID ? "Du gewinnst" : "\(name) gewinnt") \(ChipFormat.string(award.amount))\(hand)")
        }
        resultText = lines.joined(separator: "\n")
        if humanWonLastHand { Haptics.success() }
        stage = human.stack == 0 ? .busted : .handOver
    }

    // MARK: - Ereignisse animieren

    private func play(_ events: [PokerEvent]) async {
        guard let engine else { return }
        var i = 0
        while i < events.count {
            let event = events[i]
            switch event {
            case let .handStarted(_, buttonSeatID):
                self.buttonSeatID = buttonSeatID
                table.moveButton(to: buttonSeatID)

            case let .blindPosted(seatID, amount, isBig):
                lastActions[seatID] = (isBig ? "BB " : "SB ") + ChipFormat.compact(amount)
                await table.setBet(seat: seatID, amount: amount)

            case .holeCardsDealt:
                // Alle Ausgaben einsammeln und klassisch reihum (je eine Karte) austeilen
                var deals: [(Int, [Card])] = []
                while i < events.count, case let .holeCardsDealt(seatID, cards) = events[i] {
                    deals.append((seatID, cards)); i += 1
                }
                i -= 1
                for round in 0..<2 {
                    for (seatID, cards) in deals where cards.count > round {
                        await table.dealHoleCard(cards[round], seat: seatID, index: round,
                                                 isHuman: seatID == Self.humanSeatID)
                    }
                }
                seats = engine.seats

            case let .action(seatID, record):
                lastActions[seatID] = record.kind == .fold || record.kind == .check
                    ? record.kind.title
                    : "\(record.kind.title) \(ChipFormat.compact(record.streetTotal))"
                if record.kind == .fold {
                    await table.fold(seat: seatID)
                } else if record.kind != .check {
                    await table.setBet(seat: seatID, amount: record.streetTotal)
                } else {
                    Haptics.tap()
                    await sceneDelay(0.2)
                }

            case let .betsCollected(total):
                pot = total
                await table.collectBets(potTotal: total)

            case let .communityDealt(_, cards):
                // Neue Setzrunde: Aktionsanzeigen zurücksetzen (Folds bleiben sichtbar)
                lastActions = lastActions.filter { $0.value == PokerActionKind.fold.title }
                await table.dealCommunity(cards, startingAt: community.count)
                community.append(contentsOf: cards)

            case let .showdown(entries):
                for entry in entries {
                    revealedSeats.insert(entry.seatID)
                    showdownHands[entry.seatID] = entry.hand.name
                    if entry.seatID != Self.humanSeatID { await table.reveal(seat: entry.seatID) }
                }
                seats = engine.seats
                await sceneDelay(0.8)

            case let .potAwarded(award):
                let remaining = events[(i + 1)...].contains { if case .potAwarded = $0 { return true } else { return false } }
                await table.awardPot(to: award.seatID, amount: award.amount, isLast: !remaining)

            case .handFinished:
                break
            }
            i += 1
        }
        if engine.isHandInProgress { seats = engine.seats; pot = engine.pot }
    }
}
