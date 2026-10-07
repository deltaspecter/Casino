import Foundation

public enum PokerStyle: String, Codable, CaseIterable {
    /// tight-passiv: spielt wenige Hände, setzt selten
    case rock
    /// tight-aggressiv: selektiv, aber druckvoll
    case shark
    /// loose-aggressiv: viele Hände, viele Raises, blufft häufig
    case maniac
    /// loose-passiv: callt gern, raist selten
    case station

    public var title: String {
        switch self {
        case .rock: return "Fels"
        case .shark: return "Hai"
        case .maniac: return "Draufgänger"
        case .station: return "Calling Station"
        }
    }
}

public enum PokerStreet: Int, Comparable, Codable {
    case preflop, flop, turn, river, showdown

    public static func < (lhs: PokerStreet, rhs: PokerStreet) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .preflop: return "Preflop"
        case .flop: return "Flop"
        case .turn: return "Turn"
        case .river: return "River"
        case .showdown: return "Showdown"
        }
    }
}

public enum PokerAction: Equatable {
    case fold
    case check
    case call
    /// Setzen bzw. Erhöhen auf den Gesamtbetrag `to` in dieser Setzrunde.
    case raise(to: Int)
    case allIn
}

public enum PokerActionKind: String, Codable, Equatable {
    case fold, check, call, bet, raise, allIn, smallBlind, bigBlind

    public var title: String {
        switch self {
        case .fold: return "Fold"
        case .check: return "Check"
        case .call: return "Call"
        case .bet: return "Bet"
        case .raise: return "Raise"
        case .allIn: return "All-In"
        case .smallBlind: return "Small Blind"
        case .bigBlind: return "Big Blind"
        }
    }
}

public struct PokerActionRecord: Equatable {
    public let kind: PokerActionKind
    /// Gesamteinsatz des Spielers in dieser Setzrunde nach der Aktion.
    public let streetTotal: Int
}

public struct PokerSeat: Identifiable, Equatable {
    public let id: Int
    public var name: String
    public var isHuman: Bool
    public var style: PokerStyle?
    public internal(set) var stack: Int
    public internal(set) var holeCards: [Card] = []
    public internal(set) var streetBet = 0
    public internal(set) var handContribution = 0
    public internal(set) var hasFolded = false
    public internal(set) var isAllIn = false
    public internal(set) var isSittingOut = false
    public internal(set) var hasActed = false
    public internal(set) var lastAction: PokerActionRecord?

    public init(id: Int, name: String, isHuman: Bool, style: PokerStyle?, stack: Int) {
        self.id = id
        self.name = name
        self.isHuman = isHuman
        self.style = style
        self.stack = stack
    }

    /// Nimmt an der laufenden Hand teil und hat nicht gefoldet.
    public var isInHand: Bool { !isSittingOut && !hasFolded && !holeCards.isEmpty }
    /// Kann in dieser Setzrunde noch handeln.
    public var canAct: Bool { isInHand && !isAllIn }
}

public struct PokerLegalActions: Equatable {
    public let canCheck: Bool
    /// Betrag, der zum Mitgehen nachgelegt werden muss (begrenzt durch den Stack).
    public let callAmount: Int
    public let canRaise: Bool
    public let minRaiseTo: Int
    public let maxRaiseTo: Int
}

public struct ShowdownEntry: Equatable {
    public let seatID: Int
    public let hand: PokerHandRank
}

public struct PotAward: Equatable {
    public let seatID: Int
    public let amount: Int
    public let potIndex: Int
    public let handName: String?
}

public enum PokerEvent: Equatable {
    case handStarted(handNumber: Int, buttonSeatID: Int)
    case blindPosted(seatID: Int, amount: Int, isBig: Bool)
    case holeCardsDealt(seatID: Int, cards: [Card])
    case action(seatID: Int, record: PokerActionRecord)
    case betsCollected(pot: Int)
    case communityDealt(street: PokerStreet, cards: [Card])
    case showdown([ShowdownEntry])
    case potAwarded(PotAward)
    case handFinished
}

public enum PokerError: Error, Equatable {
    case notEnoughPlayers
    case handInProgress
    case notYourTurn
    case illegalAction
}

/// No-Limit Texas Hold'em nach Standardregeln, inklusive Side-Pots,
/// Heads-up-Blindregel und automatischem Run-out bei All-in.
public final class HoldemEngine {
    public let smallBlind: Int
    public let bigBlind: Int
    private let random: RandomSource

    public private(set) var seats: [PokerSeat]
    public private(set) var community: [Card] = []
    public private(set) var street: PokerStreet = .showdown
    public private(set) var buttonIndex: Int
    public private(set) var currentIndex: Int?
    public private(set) var currentBet = 0
    public private(set) var lastRaiseSize = 0
    public private(set) var handNumber = 0
    public private(set) var isHandInProgress = false
    public private(set) var lastShowdown: [ShowdownEntry] = []
    public private(set) var lastAwards: [PotAward] = []
    private var deck: [Card] = []

    public init(seats: [PokerSeat], smallBlind: Int, bigBlind: Int, random: RandomSource) {
        precondition(seats.count >= 2 && seats.count <= 9)
        precondition(smallBlind > 0 && bigBlind >= smallBlind)
        self.seats = seats
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.random = random
        // Der erste Button wird zufällig ausgelost.
        self.buttonIndex = random.uniform(seats.count)
    }

    // MARK: - Abfragen

    public var pot: Int { seats.reduce(0) { $0 + $1.handContribution } }
    /// Bereits eingesammelter Pot (ohne Einsätze der aktuellen Setzrunde).
    public var collectedPot: Int { seats.reduce(0) { $0 + $1.handContribution - $1.streetBet } }
    public var currentSeat: PokerSeat? { currentIndex.map { seats[$0] } }

    public func legalActions(forSeatAt index: Int) -> PokerLegalActions? {
        guard isHandInProgress, index == currentIndex else { return nil }
        let seat = seats[index]
        let toCall = max(0, currentBet - seat.streetBet)
        let maxTo = seat.streetBet + seat.stack
        let minTo = currentBet == 0 ? min(bigBlind, maxTo) : min(currentBet + max(lastRaiseSize, bigBlind), maxTo)
        let opponentsCanRespond = seats.indices.contains { $0 != index && seats[$0].canAct }
        return PokerLegalActions(
            canCheck: toCall == 0,
            callAmount: min(toCall, seat.stack),
            canRaise: maxTo > currentBet && opponentsCanRespond,
            minRaiseTo: minTo,
            maxRaiseTo: maxTo
        )
    }

    // MARK: - Tischverwaltung (nur zwischen den Händen)

    public func replaceSeat(at index: Int, with seat: PokerSeat) throws {
        guard !isHandInProgress else { throw PokerError.handInProgress }
        seats[index] = seat
    }

    public func setStack(_ amount: Int, forSeatAt index: Int) throws {
        guard !isHandInProgress else { throw PokerError.handInProgress }
        seats[index].stack = max(0, amount)
    }

    // MARK: - Ablauf

    @discardableResult
    public func startHand() throws -> [PokerEvent] {
        guard !isHandInProgress else { throw PokerError.handInProgress }
        guard seats.filter({ $0.stack > 0 }).count >= 2 else { throw PokerError.notEnoughPlayers }

        handNumber += 1
        isHandInProgress = true
        community = []
        lastShowdown = []
        lastAwards = []
        for i in seats.indices {
            seats[i].holeCards = []
            seats[i].streetBet = 0
            seats[i].handContribution = 0
            seats[i].hasFolded = false
            seats[i].isAllIn = false
            seats[i].hasActed = false
            seats[i].lastAction = nil
            seats[i].isSittingOut = seats[i].stack == 0
        }

        buttonIndex = nextIndex(after: buttonIndex) { !$0.isSittingOut }
        deck = Card.standardDeck()
        random.shuffle(&deck)

        var events: [PokerEvent] = [.handStarted(handNumber: handNumber, buttonSeatID: seats[buttonIndex].id)]

        let active = seats.indices.filter { !seats[$0].isSittingOut }
        let sbIndex: Int, bbIndex: Int
        if active.count == 2 {
            // Heads-up: Button zahlt den Small Blind und handelt preflop zuerst.
            sbIndex = buttonIndex
            bbIndex = nextIndex(after: buttonIndex) { !$0.isSittingOut }
        } else {
            sbIndex = nextIndex(after: buttonIndex) { !$0.isSittingOut }
            bbIndex = nextIndex(after: sbIndex) { !$0.isSittingOut }
        }
        events.append(postBlind(at: sbIndex, amount: smallBlind, isBig: false))
        events.append(postBlind(at: bbIndex, amount: bigBlind, isBig: true))
        // Ein zu kurzer Big Blind (All-in) senkt den zu deckenden Betrag.
        currentBet = seats.map(\.streetBet).max() ?? bigBlind
        lastRaiseSize = bigBlind
        street = .preflop

        // Zwei Runden à eine Karte, beginnend links vom Button
        var order: [Int] = []
        var idx = buttonIndex
        for _ in 0..<active.count {
            idx = nextIndex(after: idx) { !$0.isSittingOut }
            order.append(idx)
        }
        for _ in 0..<2 {
            for i in order { seats[i].holeCards.append(deck.removeLast()) }
        }
        for i in order {
            events.append(.holeCardsDealt(seatID: seats[i].id, cards: seats[i].holeCards))
        }

        currentIndex = nil
        if let first = firstToAct(after: bbIndex) {
            currentIndex = first
            if isBettingRoundComplete { events.append(contentsOf: advanceStreet()) }
        } else {
            events.append(contentsOf: advanceStreet())
        }
        return events
    }

    @discardableResult
    public func apply(_ action: PokerAction, forSeatAt index: Int) throws -> [PokerEvent] {
        guard isHandInProgress, index == currentIndex, let legal = legalActions(forSeatAt: index) else {
            throw PokerError.notYourTurn
        }
        var events: [PokerEvent] = []
        let seat = seats[index]

        switch action {
        case .fold:
            seats[index].hasFolded = true
            seats[index].lastAction = PokerActionRecord(kind: .fold, streetTotal: seat.streetBet)
        case .check:
            guard legal.canCheck else { throw PokerError.illegalAction }
            seats[index].lastAction = PokerActionRecord(kind: .check, streetTotal: seat.streetBet)
        case .call:
            guard legal.callAmount > 0 else { throw PokerError.illegalAction }
            commit(legal.callAmount, at: index)
            let kind: PokerActionKind = seats[index].isAllIn ? .allIn : .call
            seats[index].lastAction = PokerActionRecord(kind: kind, streetTotal: seats[index].streetBet)
        case .raise(let to):
            guard legal.canRaise, to <= legal.maxRaiseTo, to >= legal.minRaiseTo || to == legal.maxRaiseTo else {
                throw PokerError.illegalAction
            }
            applyRaise(to: to, at: index)
        case .allIn:
            if legal.maxRaiseTo > currentBet && legal.canRaise {
                applyRaise(to: legal.maxRaiseTo, at: index)
            } else if legal.callAmount > 0 {
                commit(legal.callAmount, at: index)
                seats[index].lastAction = PokerActionRecord(kind: .allIn, streetTotal: seats[index].streetBet)
            } else {
                throw PokerError.illegalAction
            }
        }
        seats[index].hasActed = true
        events.append(.action(seatID: seats[index].id, record: seats[index].lastAction!))

        let remaining = seats.indices.filter { seats[$0].isInHand }
        if remaining.count == 1 {
            events.append(contentsOf: awardUncontested(to: remaining[0]))
            return events
        }

        if isBettingRoundComplete {
            events.append(contentsOf: advanceStreet())
        } else {
            currentIndex = nextIndex(after: index) { $0.canAct }
        }
        return events
    }

    // MARK: - Interna

    private func applyRaise(to: Int, at index: Int) {
        let previousBet = currentBet
        let wasBet = previousBet == 0
        commit(to - seats[index].streetBet, at: index)
        let raiseSize = to - previousBet
        if raiseSize >= lastRaiseSize {
            lastRaiseSize = raiseSize
        }
        currentBet = max(currentBet, to)
        // Erneute Handlungsmöglichkeit für alle anderen
        for i in seats.indices where i != index && seats[i].canAct { seats[i].hasActed = false }
        let kind: PokerActionKind = seats[index].isAllIn ? .allIn : (wasBet ? .bet : .raise)
        seats[index].lastAction = PokerActionRecord(kind: kind, streetTotal: seats[index].streetBet)
    }

    private func commit(_ amount: Int, at index: Int) {
        let amount = min(amount, seats[index].stack)
        seats[index].stack -= amount
        seats[index].streetBet += amount
        seats[index].handContribution += amount
        if seats[index].stack == 0 { seats[index].isAllIn = true }
    }

    private func postBlind(at index: Int, amount: Int, isBig: Bool) -> PokerEvent {
        commit(amount, at: index)
        seats[index].lastAction = PokerActionRecord(kind: isBig ? .bigBlind : .smallBlind, streetTotal: seats[index].streetBet)
        return .blindPosted(seatID: seats[index].id, amount: seats[index].streetBet, isBig: isBig)
    }

    private var isBettingRoundComplete: Bool {
        let actors = seats.filter(\.canAct)
        if actors.isEmpty { return true }
        if actors.count == 1 {
            // Alle anderen sind all-in: Wer den Einsatz bereits gedeckt hat, muss nicht mehr handeln.
            return actors[0].streetBet >= currentBet
        }
        return actors.allSatisfy { $0.hasActed && $0.streetBet == currentBet }
    }

    private func firstToAct(after index: Int) -> Int? {
        guard seats.contains(where: \.canAct) else { return nil }
        return nextIndex(after: index) { $0.canAct }
    }

    private func nextIndex(after index: Int, where predicate: (PokerSeat) -> Bool) -> Int {
        var i = index
        for _ in 0..<seats.count {
            i = (i + 1) % seats.count
            if predicate(seats[i]) { return i }
        }
        return index
    }

    private func advanceStreet() -> [PokerEvent] {
        var events: [PokerEvent] = []
        while true {
            for i in seats.indices {
                seats[i].streetBet = 0
                seats[i].hasActed = false
            }
            currentBet = 0
            lastRaiseSize = bigBlind
            events.append(.betsCollected(pot: pot))

            guard street < .river else {
                events.append(contentsOf: showdown())
                return events
            }

            street = PokerStreet(rawValue: street.rawValue + 1)!
            _ = deck.removeLast() // Burn-Karte
            let count = street == .flop ? 3 : 1
            var newCards: [Card] = []
            for _ in 0..<count { newCards.append(deck.removeLast()) }
            community.append(contentsOf: newCards)
            events.append(.communityDealt(street: street, cards: newCards))

            // Weiter setzen nur, wenn mindestens zwei Spieler noch handeln können
            if seats.filter(\.canAct).count >= 2 {
                currentIndex = nextIndex(after: buttonIndex) { $0.canAct }
                return events
            }
            currentIndex = nil
        }
    }

    private func awardUncontested(to index: Int) -> [PokerEvent] {
        let amount = pot
        seats[index].stack += amount
        let award = PotAward(seatID: seats[index].id, amount: amount, potIndex: 0, handName: nil)
        lastAwards = [award]
        finishHand()
        return [.betsCollected(pot: amount), .potAwarded(award), .handFinished]
    }

    /// Teilt den Gesamtpot in Haupt- und Side-Pots auf.
    func buildPots() -> [(amount: Int, eligible: [Int])] {
        var remaining = seats.map(\.handContribution)
        var pots: [(amount: Int, eligible: [Int])] = []
        while true {
            let eligible = seats.indices.filter { seats[$0].isInHand && remaining[$0] > 0 }
            guard let level = eligible.map({ remaining[$0] }).min() else { break }
            var amount = 0
            for i in seats.indices {
                let take = min(remaining[i], level)
                amount += take
                remaining[i] -= take
            }
            pots.append((amount, eligible))
        }
        // Übrige Beiträge gefoldeter Spieler fallen in den letzten Pot.
        let leftover = remaining.reduce(0, +)
        if leftover > 0, !pots.isEmpty { pots[pots.count - 1].amount += leftover }
        return pots
    }

    private func showdown() -> [PokerEvent] {
        street = .showdown
        currentIndex = nil
        let contenders = seats.indices.filter { seats[$0].isInHand }
        var ranks: [Int: PokerHandRank] = [:]
        for i in contenders { ranks[i] = HandEvaluator.bestHand(seats[i].holeCards + community) }
        lastShowdown = contenders.map { ShowdownEntry(seatID: seats[$0].id, hand: ranks[$0]!) }

        var events: [PokerEvent] = [.showdown(lastShowdown)]
        var awards: [PotAward] = []
        for (potIndex, pot) in buildPots().enumerated() {
            let best = pot.eligible.compactMap { ranks[$0] }.max()!
            // Gewinner in Sitzreihenfolge ab links vom Button (für ungerade Restchips)
            let winners = orderFromButton(pot.eligible.filter { ranks[$0]! == best })
            let share = pot.amount / winners.count
            var oddChips = pot.amount % winners.count
            for w in winners {
                var amount = share
                if oddChips > 0 { amount += 1; oddChips -= 1 }
                seats[w].stack += amount
                let name = pot.eligible.count > 1 ? best.name : nil
                awards.append(PotAward(seatID: seats[w].id, amount: amount, potIndex: potIndex, handName: name))
            }
        }
        lastAwards = awards
        events.append(contentsOf: awards.map(PokerEvent.potAwarded))
        finishHand()
        events.append(.handFinished)
        return events
    }

    private func orderFromButton(_ indices: [Int]) -> [Int] {
        indices.sorted { lhs, rhs in
            let l = (lhs - buttonIndex - 1 + seats.count) % seats.count
            let r = (rhs - buttonIndex - 1 + seats.count) % seats.count
            return l < r
        }
    }

    private func finishHand() {
        isHandInProgress = false
        currentIndex = nil
        for i in seats.indices { seats[i].streetBet = 0 }
    }
}
