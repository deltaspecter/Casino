import Foundation

/// Tischregeln von BlackCasino (im Spiel unter „Rules“ einsehbar):
/// * 1 Standard-Deck (52 Karten), **vor jeder Runde vollständig neu gemischt** –
///   dadurch ist jede Runde unabhängig von allen vorherigen.
/// * Dealer erhält eine offene und eine verdeckte Karte und prüft bei Ass oder 10er auf Blackjack (Peek).
/// * Dealer zieht bis 16 und **steht auf allen 17** (auch Soft 17, „S17“).
/// * Blackjack zahlt 3:2, normaler Gewinn 1:1, Push gibt den Einsatz zurück.
/// * Double Down auf beliebige erste zwei Karten (auch nach Split), genau eine weitere Karte.
/// * Split bei zwei Karten gleichen Werts, bis zu 4 Hände; geteilte Asse erhalten je eine Karte
///   und dürfen nicht erneut geteilt werden. 21 nach Split zählt nicht als Blackjack.
/// * Keine Insurance, kein Surrender.
public struct BlackjackRules: Equatable {
    public var deckCount = 1
    public var dealerHitsSoft17 = false
    public var doubleAfterSplit = true
    public var maxHands = 4
    public var resplitAces = false
    public var minBet = 10
    public var maxBet = 5_000

    public init() {}

    public init(minBet: Int, maxBet: Int) {
        self.minBet = minBet
        self.maxBet = maxBet
    }
}

public enum BlackjackPhase: Equatable {
    case betting, playerTurn, dealerTurn, settled
}

public enum BlackjackAction: String, CaseIterable, Equatable {
    case hit, stand, double, split
}

public enum BlackjackEvent: Equatable {
    case shuffled
    case dealtToPlayer(handID: Int, card: Card)
    case dealtToDealer(card: Card, faceDown: Bool)
    case holeCardRevealed(Card)
    case split(originalHandID: Int, newHandID: Int, movedCard: Card)
    case doubled(handID: Int)
    case activeHandChanged(handID: Int?)
    case settled([HandResult])
}

public enum BlackjackError: Error, Equatable {
    case invalidPhase
    case invalidBet
    case illegalAction(BlackjackAction)
}

/// Regelbasierte Blackjack-Engine. Sie kennt keinen Kontostand und trifft keine
/// Entscheidungen über Ergebnisse – Karten kommen ausschließlich aus dem gemischten Schlitten,
/// der Dealer folgt festen Regeln.
public final class BlackjackEngine {
    public let rules: BlackjackRules
    private let random: RandomSource

    public private(set) var shoe: Shoe
    public private(set) var phase: BlackjackPhase = .betting
    public private(set) var hands: [BlackjackHand] = []
    public private(set) var dealerCards: [Card] = []
    public private(set) var isHoleCardRevealed = false
    public private(set) var activeHandIndex: Int?
    public private(set) var results: [HandResult] = []
    private var nextHandID = 0
    /// Nur für Unit-Tests (über `@testable import` erreichbar): feste Kartenreihenfolge
    /// für die nächste Runde, um Regel-Szenarien gezielt zu prüfen. Die App kann dies nicht setzen.
    var testDeckForNextRound: [Card]?

    public init(rules: BlackjackRules = BlackjackRules(), random: RandomSource) {
        self.rules = rules
        self.random = random
        self.shoe = Shoe(deckCount: rules.deckCount, random: random)
    }

    // MARK: - Abfragen

    public var activeHand: BlackjackHand? {
        activeHandIndex.map { hands[$0] }
    }

    /// Für den Spieler sichtbarer Dealer-Wert (nur offene Karten).
    public var dealerVisibleValue: HandValue {
        HandValue.of(isHoleCardRevealed ? dealerCards : Array(dealerCards.prefix(1)))
    }

    public var totalStake: Int { hands.reduce(0) { $0 + $1.bet } }

    public func availableActions() -> Set<BlackjackAction> {
        guard phase == .playerTurn, let hand = activeHand, !hand.isFinished else { return [] }
        var actions: Set<BlackjackAction> = [.hit, .stand]
        if hand.cards.count == 2 && !hand.isSplitAces && (!hand.isFromSplit || rules.doubleAfterSplit) {
            actions.insert(.double)
        }
        if hand.cards.count == 2,
           hand.cards[0].rank.blackjackValue == hand.cards[1].rank.blackjackValue,
           hands.count < rules.maxHands,
           !hand.isSplitAces || rules.resplitAces {
            actions.insert(.split)
        }
        return actions
    }

    /// Zusätzlicher Einsatz, den eine Aktion erfordert (für Double und Split).
    public func additionalStake(for action: BlackjackAction) -> Int {
        switch action {
        case .double, .split: return activeHand?.bet ?? 0
        case .hit, .stand: return 0
        }
    }

    // MARK: - Ablauf

    @discardableResult
    public func startRound(bet: Int) throws -> [BlackjackEvent] {
        guard phase == .betting || phase == .settled else { throw BlackjackError.invalidPhase }
        guard bet >= rules.minBet && bet <= rules.maxBet else { throw BlackjackError.invalidBet }

        var events: [BlackjackEvent] = []
        hands = []
        dealerCards = []
        results = []
        isHoleCardRevealed = false
        activeHandIndex = nil
        nextHandID = 0

        // RNG → Mischen → Ausgabe → Regeln → Ergebnis. Jede Runde startet mit frisch gemischtem Deck.
        if let testDeck = testDeckForNextRound {
            shoe.setOrderForTesting(testDeck)
            testDeckForNextRound = nil
        } else {
            shoe.reshuffle(random: random)
        }
        events.append(.shuffled)

        hands.append(BlackjackHand(id: makeHandID(), cards: [], bet: bet))

        // Klassische Ausgabe: Spieler, Dealer (offen), Spieler, Dealer (verdeckt)
        events.append(dealToHand(0))
        events.append(dealToDealer(faceDown: false))
        events.append(dealToHand(0))
        events.append(dealToDealer(faceDown: true))

        let dealerHasBlackjack = HandValue.of(dealerCards).total == 21
        if dealerHasBlackjack || hands[0].isBlackjack {
            // Peek bzw. Spieler-Blackjack: Runde endet sofort.
            events.append(revealHoleCard())
            events.append(settle())
            return events
        }

        phase = .playerTurn
        activeHandIndex = 0
        events.append(.activeHandChanged(handID: hands[0].id))
        return events
    }

    @discardableResult
    public func perform(_ action: BlackjackAction) throws -> [BlackjackEvent] {
        guard phase == .playerTurn, let index = activeHandIndex else { throw BlackjackError.invalidPhase }
        guard availableActions().contains(action) else { throw BlackjackError.illegalAction(action) }

        var events: [BlackjackEvent] = []
        switch action {
        case .hit:
            events.append(dealToHand(index))
        case .stand:
            hands[index].isStood = true
        case .double:
            hands[index].bet *= 2
            hands[index].isDoubled = true
            events.append(.doubled(handID: hands[index].id))
            events.append(dealToHand(index))
        case .split:
            events.append(contentsOf: split(at: index))
        }

        if hands[index].isFinished {
            events.append(contentsOf: advance())
        }
        return events
    }

    // MARK: - Interna

    private func makeHandID() -> Int {
        defer { nextHandID += 1 }
        return nextHandID
    }

    private func dealToHand(_ index: Int) -> BlackjackEvent {
        let card = shoe.draw(random: random)
        hands[index].cards.append(card)
        return .dealtToPlayer(handID: hands[index].id, card: card)
    }

    private func dealToDealer(faceDown: Bool) -> BlackjackEvent {
        let card = shoe.draw(random: random)
        dealerCards.append(card)
        return .dealtToDealer(card: card, faceDown: faceDown)
    }

    private func revealHoleCard() -> BlackjackEvent {
        isHoleCardRevealed = true
        return .holeCardRevealed(dealerCards[1])
    }

    private func split(at index: Int) -> [BlackjackEvent] {
        let original = hands[index]
        let moved = original.cards[1]
        let aces = original.cards[0].rank == .ace

        let first = BlackjackHand(id: original.id, cards: [original.cards[0]], bet: original.bet,
                                  isFromSplit: true, isSplitAces: aces)
        let second = BlackjackHand(id: makeHandID(), cards: [moved], bet: original.bet,
                                   isFromSplit: true, isSplitAces: aces)
        hands[index] = first
        hands.insert(second, at: index + 1)

        return [
            .split(originalHandID: first.id, newHandID: second.id, movedCard: moved),
            dealToHand(index),
            dealToHand(index + 1)
        ]
    }

    /// Wechselt zur nächsten offenen Hand oder startet den Dealer-Zug.
    private func advance() -> [BlackjackEvent] {
        let start = (activeHandIndex ?? -1) + 1
        if let next = hands.indices.first(where: { $0 >= start && !hands[$0].isFinished }) {
            activeHandIndex = next
            return [.activeHandChanged(handID: hands[next].id)]
        }
        activeHandIndex = nil
        return [.activeHandChanged(handID: nil)] + playDealer()
    }

    private func playDealer() -> [BlackjackEvent] {
        phase = .dealerTurn
        var events = [revealHoleCard()]
        // Sind alle Spielerhände überkauft, muss der Dealer nicht weiterziehen.
        if hands.contains(where: { !$0.isBust }) {
            while shouldDealerHit {
                events.append(dealToDealer(faceDown: false))
            }
        }
        events.append(settle())
        return events
    }

    private var shouldDealerHit: Bool {
        let value = HandValue.of(dealerCards)
        if value.total < 17 { return true }
        return value.total == 17 && value.isSoft && rules.dealerHitsSoft17
    }

    private func settle() -> BlackjackEvent {
        let dealer = HandValue.of(dealerCards)
        let dealerBlackjack = dealerCards.count == 2 && dealer.total == 21

        results = hands.map { hand in
            let outcome: HandOutcome
            let payout: Int
            if hand.isBust {
                outcome = .bust; payout = 0
            } else if hand.isBlackjack && !dealerBlackjack {
                outcome = .blackjack; payout = hand.bet + (hand.bet * 3) / 2
            } else if dealerBlackjack {
                outcome = hand.isBlackjack ? .push : .lose
                payout = hand.isBlackjack ? hand.bet : 0
            } else if dealer.total > 21 || hand.value.total > dealer.total {
                outcome = .win; payout = hand.bet * 2
            } else if hand.value.total == dealer.total {
                outcome = .push; payout = hand.bet
            } else {
                outcome = .lose; payout = 0
            }
            return HandResult(handID: hand.id, outcome: outcome, stake: hand.bet, payout: payout)
        }
        phase = .settled
        activeHandIndex = nil
        return .settled(results)
    }
}
