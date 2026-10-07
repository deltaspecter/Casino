import SwiftUI
import Observation
import CasinoCore

/// Verbindet Engine (Regeln), 3D-Tisch (Darstellung) und App-Modell (Chips/Fortschritt).
@MainActor
@Observable
final class BlackjackViewModel {
    enum Stage: Equatable { case betting, busy, playerTurn, roundOver }

    struct VisibleHand: Identifiable, Equatable {
        let id: Int
        var cards: [Card]
        var bet: Int
        var isActive = false
        var result: HandResult?
        var value: HandValue { HandValue.of(cards) }
    }

    struct RoundSummary: Equatable {
        let title: String
        let net: Int
        let isWin: Bool
    }

    static let chipValues = [5, 25, 100, 500, 1_000, 5_000]

    private(set) var stage: Stage = .betting
    var pendingBet = 0
    private(set) var lastBet = 0
    private(set) var hands: [VisibleHand] = []
    private(set) var dealerCards: [Card] = []
    private(set) var holeHidden = false
    private(set) var actions: Set<BlackjackAction> = []
    private(set) var summary: RoundSummary?
    var anchors: [String: CGPoint] = [:]

    let rules: BlackjackRules
    @ObservationIgnored let table: BlackjackTable
    @ObservationIgnored private let engine: BlackjackEngine
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var roundCredited = true

    init(app: AppModel) {
        self.app = app
        rules = BlackjackRules(minBet: 10, maxBet: 10_000)
        engine = BlackjackEngine(rules: rules, random: app.random)
        table = BlackjackTable(reducedEffects: app.profile.settings.reducedMotion)
        pendingBet = min(100, max(rules.minBet, app.chips))
    }

    // MARK: - Anzeige

    var dealerValueText: String? {
        guard !dealerCards.isEmpty else { return nil }
        let visible = holeHidden ? Array(dealerCards.prefix(1)) : dealerCards
        return HandValue.of(visible).display
    }

    var activeHand: VisibleHand? { hands.first { $0.isActive } }

    func extraStakeNeeded(for action: BlackjackAction) -> Int { engine.additionalStake(for: action) }

    func canAfford(_ action: BlackjackAction) -> Bool {
        extraStakeNeeded(for: action) <= (app?.chips ?? 0)
    }

    // MARK: - Einsatz

    func addChip(_ value: Int) {
        guard stage == .betting || stage == .roundOver, let app else { return }
        let target = min(pendingBet + value, rules.maxBet, app.chips)
        if target == pendingBet { Haptics.warning(); return }
        pendingBet = target
        Haptics.chip()
    }

    func clearBet() {
        pendingBet = 0
        Haptics.tap()
    }

    func repeatLastBet() {
        guard let app, lastBet > 0 else { return }
        pendingBet = min(lastBet, app.chips, rules.maxBet)
    }

    // MARK: - Ablauf

    func deal() async {
        guard let app, stage == .betting || stage == .roundOver else { return }
        if stage == .roundOver { await resetTable() }
        guard pendingBet >= rules.minBet else {
            app.show(Toast(icon: "exclamationmark.circle", title: "Mindesteinsatz \(rules.minBet)", subtitle: nil, tint: Theme.red))
            return
        }
        let bet = pendingBet
        guard app.moveToTable(bet) else { return }

        stage = .busy
        lastBet = bet
        summary = nil
        roundCredited = false
        hands = [VisibleHand(id: 0, cards: [], bet: bet)]
        await table.placeBet(handID: 0, amount: bet)

        do {
            let events = try engine.startRound(bet: bet)
            await play(events)
        } catch {
            app.releaseFromTable(stake: bet, payout: bet)
            roundCredited = true
            stage = .betting
        }
    }

    func perform(_ action: BlackjackAction) async {
        guard let app, stage == .playerTurn, actions.contains(action) else { return }
        let extra = engine.additionalStake(for: action)
        if extra > 0 { guard app.moveToTable(extra) else { return } }
        Haptics.tap()
        stage = .busy
        do {
            let events = try engine.perform(action)
            await play(events)
        } catch {
            if extra > 0 { app.releaseFromTable(stake: extra, payout: extra) }
            stage = .playerTurn
        }
    }

    func newRound() async {
        await resetTable()
        if let app { pendingBet = min(lastBet, app.chips, rules.maxBet) }
    }

    private func resetTable() async {
        stage = .busy
        summary = nil
        await table.clear()
        hands = []
        dealerCards = []
        holeHidden = false
        actions = []
        stage = .betting
    }

    /// Beim Verlassen: offene Hände werden regelkonform mit „Stand“ beendet und abgerechnet.
    func leave() {
        while engine.phase == .playerTurn {
            if (try? engine.perform(.stand)) == nil { break }
        }
        if engine.phase == .settled { credit(engine.results) }
    }

    // MARK: - Ereignisse abspielen

    private func play(_ events: [BlackjackEvent]) async {
        var doubled = Set<Int>()
        for event in events {
            switch event {
            case .shuffled:
                app?.show(Toast(icon: "shuffle", title: "Neuer Schlitten", subtitle: "6 Decks wurden frisch gemischt"))
                await sceneDelay(0.3)

            case let .dealtToPlayer(handID, card):
                await table.dealToPlayer(handID: handID, card: card, rotated: doubled.contains(handID))
                if let i = hands.firstIndex(where: { $0.id == handID }) { hands[i].cards.append(card) }

            case let .dealtToDealer(card, faceDown):
                await table.dealToDealer(card: card, faceDown: faceDown)
                dealerCards.append(card)
                if faceDown { holeHidden = true }

            case .holeCardRevealed:
                await table.revealHoleCard()
                holeHidden = false
                await sceneDelay(0.25)

            case let .split(originalID, newID, movedCard):
                if let i = hands.firstIndex(where: { $0.id == originalID }) {
                    if hands[i].cards.last == movedCard { hands[i].cards.removeLast() }
                    hands.insert(VisibleHand(id: newID, cards: [movedCard], bet: hands[i].bet), at: i + 1)
                }
                await table.split(originalID: originalID, newID: newID)

            case let .doubled(handID):
                doubled.insert(handID)
                if let i = hands.firstIndex(where: { $0.id == handID }) {
                    hands[i].bet *= 2
                    await table.updateBet(handID: handID, amount: hands[i].bet)
                }

            case let .activeHandChanged(handID):
                for i in hands.indices { hands[i].isActive = hands[i].id == handID }

            case let .settled(results):
                credit(results)
                for result in results {
                    if let i = hands.firstIndex(where: { $0.id == result.handID }) { hands[i].result = result }
                }
                await table.settle(results)
            }
        }
        actions = engine.availableActions()
        switch engine.phase {
        case .playerTurn: stage = .playerTurn
        case .settled: stage = .roundOver
        case .betting, .dealerTurn: break
        }
    }

    /// Bucht das Ergebnis genau einmal (auch wenn die Animation noch läuft oder abgebrochen wird).
    private func credit(_ results: [HandResult]) {
        guard !roundCredited, let app else { return }
        roundCredited = true
        let stake = results.reduce(0) { $0 + $1.stake }
        let payout = results.reduce(0) { $0 + $1.payout }
        app.releaseFromTable(stake: stake, payout: payout)
        app.record(.blackjackRound(
            stake: stake,
            payout: payout,
            handsWon: results.filter { $0.outcome == .win || $0.outcome == .blackjack }.count,
            blackjacks: results.filter { $0.outcome == .blackjack }.count,
            hands: results.count
        ))

        let net = payout - stake
        let title: String
        if results.count == 1 {
            title = results[0].outcome.title
        } else {
            title = net > 0 ? "GEWONNEN" : net < 0 ? "VERLOREN" : "PUSH"
        }
        summary = RoundSummary(title: title, net: net, isWin: net > 0)
        if net > 0 { Haptics.success() } else if net < 0 { Haptics.thud() }
    }
}
