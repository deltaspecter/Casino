import Foundation

/// Ergebnis aller Hände eines Sitzplatzes.
public struct SeatResult: Equatable, Codable {
    public let seatID: Int
    public let results: [HandResult]

    public var stake: Int { results.reduce(0) { $0 + $1.stake } }
    public var payout: Int { results.reduce(0) { $0 + $1.payout } }
}

public struct BlackjackSeat: Equatable {
    public let seatID: Int
    public internal(set) var hands: [BlackjackHand]
    public internal(set) var results: [HandResult] = []

    public var totalStake: Int { hands.reduce(0) { $0 + $1.bet } }
}

public enum BlackjackTableEvent: Equatable {
    case shuffled
    case dealtToPlayer(seatID: Int, handID: Int, card: Card)
    case dealtToDealer(card: Card, faceDown: Bool)
    case holeCardRevealed(Card)
    case split(seatID: Int, originalHandID: Int, newHandID: Int, movedCard: Card)
    case doubled(seatID: Int, handID: Int)
    case turnChanged(seatID: Int?, handID: Int?)
    case settled([SeatResult])
}

/// Blackjack-Tisch mit einem oder mehreren Sitzplätzen gegen **einen** Dealer.
///
/// Dies ist die einzige Blackjack-Regelimplementierung von BlackCasino. Offline nutzt
/// `BlackjackEngine` sie mit einem Platz, online führt der Server sie autoritativ aus.
/// Regeln: siehe `BlackjackRules`.
///
/// * Jeder Platz hat eigene Hände; Aktionen eines Platzes betreffen nur dessen Hände.
/// * Kartenreihenfolge: Runde 1 an alle Plätze (in Sitzreihenfolge), Dealer offen,
///   Runde 2 an alle Plätze, Dealer verdeckt. Danach zieht jede Aktion die oberste Karte.
/// * Die Plätze sind nacheinander am Zug; innerhalb eines Platzes die Hände von links nach rechts.
public final class BlackjackTableEngine {
    public let rules: BlackjackRules
    private let random: RandomSource

    public private(set) var shoe: Shoe
    public private(set) var phase: BlackjackPhase = .betting
    public private(set) var seats: [BlackjackSeat] = []
    public private(set) var dealerCards: [Card] = []
    public private(set) var isHoleCardRevealed = false
    /// Aktueller Zug: Index in `seats` und Index der Hand.
    public private(set) var turn: (seat: Int, hand: Int)?
    private var nextHandID = 0

    /// Nur für Unit-Tests (über `@testable import`): feste Ziehreihenfolge der nächsten Runde.
    var testDeckForNextRound: [Card]?

    public init(rules: BlackjackRules = BlackjackRules(), random: RandomSource) {
        self.rules = rules
        self.random = random
        self.shoe = Shoe(deckCount: rules.deckCount, random: random)
    }

    // MARK: - Abfragen

    public var currentSeatID: Int? { turn.map { seats[$0.seat].seatID } }
    public var currentHand: BlackjackHand? { turn.map { seats[$0.seat].hands[$0.hand] } }

    public func seat(_ seatID: Int) -> BlackjackSeat? { seats.first { $0.seatID == seatID } }

    /// Für Spieler sichtbarer Dealer-Wert (nur offene Karten).
    public var dealerVisibleValue: HandValue {
        HandValue.of(isHoleCardRevealed ? dealerCards : Array(dealerCards.prefix(1)))
    }

    /// Erlaubte Aktionen – ausschließlich für den Platz, der gerade am Zug ist.
    public func availableActions(forSeat seatID: Int) -> Set<BlackjackAction> {
        guard phase == .playerTurn, let turn, seats[turn.seat].seatID == seatID else { return [] }
        let seat = seats[turn.seat]
        let hand = seat.hands[turn.hand]
        guard !hand.isFinished else { return [] }
        var actions: Set<BlackjackAction> = [.hit, .stand]
        if hand.cards.count == 2 && !hand.isSplitAces && (!hand.isFromSplit || rules.doubleAfterSplit) {
            actions.insert(.double)
        }
        if hand.cards.count == 2,
           hand.cards[0].rank.blackjackValue == hand.cards[1].rank.blackjackValue,
           seat.hands.count < rules.maxHands,
           !hand.isSplitAces || rules.resplitAces {
            actions.insert(.split)
        }
        return actions
    }

    /// Zusätzlicher Einsatz für Double oder Split.
    public func additionalStake(for action: BlackjackAction, seat seatID: Int) -> Int {
        guard currentSeatID == seatID, let hand = currentHand else { return 0 }
        switch action {
        case .double, .split: return hand.bet
        case .hit, .stand: return 0
        }
    }

    // MARK: - Ablauf

    /// Startet eine Runde. `bets` in Sitzreihenfolge; jeder Platz höchstens einmal.
    @discardableResult
    public func startRound(bets: [(seatID: Int, bet: Int)]) throws -> [BlackjackTableEvent] {
        guard phase == .betting || phase == .settled else { throw BlackjackError.invalidPhase }
        guard !bets.isEmpty, Set(bets.map(\.seatID)).count == bets.count else { throw BlackjackError.invalidBet }
        guard bets.allSatisfy({ $0.bet >= rules.minBet && $0.bet <= rules.maxBet }) else { throw BlackjackError.invalidBet }

        var events: [BlackjackTableEvent] = []
        dealerCards = []
        isHoleCardRevealed = false
        turn = nil
        nextHandID = 0

        // RNG → Mischen → Ausgabe → Regeln → Ergebnis. Jede Runde mit frisch gemischtem Deck.
        if let testDeck = testDeckForNextRound {
            shoe.setOrderForTesting(testDeck)
            testDeckForNextRound = nil
        } else {
            shoe.reshuffle(random: random)
        }
        events.append(.shuffled)

        seats = bets.map { BlackjackSeat(seatID: $0.seatID, hands: [BlackjackHand(id: makeHandID(), cards: [], bet: $0.bet)]) }

        for i in seats.indices { events.append(deal(toSeat: i, hand: 0)) }
        events.append(dealToDealer(faceDown: false))
        for i in seats.indices { events.append(deal(toSeat: i, hand: 0)) }
        events.append(dealToDealer(faceDown: true))

        let dealerHasBlackjack = HandValue.of(dealerCards).total == 21
        if dealerHasBlackjack || !hasLiveHands {
            // Peek: Dealer-Blackjack beendet die Runde sofort. Haben alle Spieler Blackjack,
            // gibt es nichts mehr zu entscheiden.
            events.append(revealHoleCard())
            events.append(settle())
            return events
        }

        phase = .playerTurn
        turn = nextTurn(after: nil)
        events.append(turnEvent())
        return events
    }

    @discardableResult
    public func perform(_ action: BlackjackAction, seat seatID: Int) throws -> [BlackjackTableEvent] {
        guard phase == .playerTurn, let turn else { throw BlackjackError.invalidPhase }
        guard seats[turn.seat].seatID == seatID else { throw BlackjackError.notYourTurn }
        guard availableActions(forSeat: seatID).contains(action) else { throw BlackjackError.illegalAction(action) }

        var events: [BlackjackTableEvent] = []
        let s = turn.seat, h = turn.hand
        switch action {
        case .hit:
            events.append(deal(toSeat: s, hand: h))
        case .stand:
            seats[s].hands[h].isStood = true
        case .double:
            seats[s].hands[h].bet *= 2
            seats[s].hands[h].isDoubled = true
            events.append(.doubled(seatID: seatID, handID: seats[s].hands[h].id))
            events.append(deal(toSeat: s, hand: h))
        case .split:
            events.append(contentsOf: split(seat: s, hand: h))
        }

        if seats[s].hands[h].isFinished {
            events.append(contentsOf: advance())
        }
        return events
    }

    // MARK: - Interna

    private func makeHandID() -> Int {
        defer { nextHandID += 1 }
        return nextHandID
    }

    /// Eine Hand ist „lebendig“, wenn der Dealer gegen sie noch ziehen muss.
    private var hasLiveHands: Bool {
        seats.contains { $0.hands.contains { !$0.isBust && !$0.isBlackjack } }
    }

    private func deal(toSeat s: Int, hand h: Int) -> BlackjackTableEvent {
        let card = shoe.draw(random: random)
        seats[s].hands[h].cards.append(card)
        return .dealtToPlayer(seatID: seats[s].seatID, handID: seats[s].hands[h].id, card: card)
    }

    private func dealToDealer(faceDown: Bool) -> BlackjackTableEvent {
        let card = shoe.draw(random: random)
        dealerCards.append(card)
        return .dealtToDealer(card: card, faceDown: faceDown)
    }

    private func revealHoleCard() -> BlackjackTableEvent {
        isHoleCardRevealed = true
        return .holeCardRevealed(dealerCards[1])
    }

    private func split(seat s: Int, hand h: Int) -> [BlackjackTableEvent] {
        let original = seats[s].hands[h]
        let moved = original.cards[1]
        let aces = original.cards[0].rank == .ace
        let first = BlackjackHand(id: original.id, cards: [original.cards[0]], bet: original.bet,
                                  isFromSplit: true, isSplitAces: aces)
        let second = BlackjackHand(id: makeHandID(), cards: [moved], bet: original.bet,
                                   isFromSplit: true, isSplitAces: aces)
        seats[s].hands[h] = first
        seats[s].hands.insert(second, at: h + 1)
        return [
            .split(seatID: seats[s].seatID, originalHandID: first.id, newHandID: second.id, movedCard: moved),
            deal(toSeat: s, hand: h),
            deal(toSeat: s, hand: h + 1)
        ]
    }

    private func turnEvent() -> BlackjackTableEvent {
        guard let turn else { return .turnChanged(seatID: nil, handID: nil) }
        return .turnChanged(seatID: seats[turn.seat].seatID, handID: seats[turn.seat].hands[turn.hand].id)
    }

    /// Nächste offene Hand: zuerst weitere Hände desselben Platzes, dann die folgenden Plätze.
    private func nextTurn(after current: (seat: Int, hand: Int)?) -> (seat: Int, hand: Int)? {
        var s = current?.seat ?? 0
        var h = current.map { $0.hand + 1 } ?? 0
        while s < seats.count {
            while h < seats[s].hands.count {
                if !seats[s].hands[h].isFinished { return (s, h) }
                h += 1
            }
            s += 1
            h = 0
        }
        return nil
    }

    private func advance() -> [BlackjackTableEvent] {
        turn = nextTurn(after: turn)
        if turn != nil { return [turnEvent()] }
        return [.turnChanged(seatID: nil, handID: nil)] + playDealer()
    }

    /// Wenn ein Platz den Tisch verlässt oder die Bedenkzeit abläuft: alle seine offenen Hände stehen lassen.
    @discardableResult
    public func standAll(seat seatID: Int) -> [BlackjackTableEvent] {
        var events: [BlackjackTableEvent] = []
        while phase == .playerTurn, currentSeatID == seatID {
            if let e = try? perform(.stand, seat: seatID) { events += e } else { break }
        }
        return events
    }

    private func playDealer() -> [BlackjackTableEvent] {
        phase = .dealerTurn
        var events = [revealHoleCard()]
        // Der Dealer zieht nur, wenn noch Hände offen sind, die nicht überkauft und kein Blackjack sind.
        if hasLiveHands {
            while shouldDealerHit { events.append(dealToDealer(faceDown: false)) }
        }
        events.append(settle())
        return events
    }

    private var shouldDealerHit: Bool {
        let value = HandValue.of(dealerCards)
        if value.total < 17 { return true }
        return value.total == 17 && value.isSoft && rules.dealerHitsSoft17
    }

    private func settle() -> BlackjackTableEvent {
        let dealer = HandValue.of(dealerCards)
        let dealerBlackjack = dealerCards.count == 2 && dealer.total == 21

        for s in seats.indices {
            seats[s].results = seats[s].hands.map { hand in
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
        }
        phase = .settled
        turn = nil
        return .settled(seats.map { SeatResult(seatID: $0.seatID, results: $0.results) })
    }
}
