import Foundation

/// Alles, was ein KI-Gegner sehen darf: eigene Karten, Board, Pot und Einsätze.
/// Die verdeckten Karten anderer Spieler und die Reihenfolge des Decks sind
/// bewusst **nicht** enthalten – die KI spielt fair.
public struct PokerAIContext {
    public let holeCards: [Card]
    public let community: [Card]
    public let pot: Int
    public let currentBet: Int
    public let streetBet: Int
    public let stack: Int
    public let bigBlind: Int
    public let activeOpponents: Int
    public let legal: PokerLegalActions

    public init(engine: HoldemEngine, seatIndex: Int) {
        let seat = engine.seats[seatIndex]
        holeCards = seat.holeCards
        community = engine.community
        pot = engine.pot
        currentBet = engine.currentBet
        streetBet = seat.streetBet
        stack = seat.stack
        bigBlind = engine.bigBlind
        activeOpponents = engine.seats.filter(\.isInHand).count - 1
        legal = engine.legalActions(forSeatAt: seatIndex)!
    }
}

public struct PokerAIProfile {
    /// Zuschlag auf die benötigte Equity (positiv = tighter).
    public let tightness: Double
    /// Wahrscheinlichkeit, mit einer starken Hand zu setzen/erhöhen statt passiv zu spielen.
    public let aggression: Double
    /// Bluff-Häufigkeit mit schwachen Händen.
    public let bluffRate: Double
    /// Bereitschaft, mit Grenzhänden zu callen.
    public let stickiness: Double

    public static func `for`(_ style: PokerStyle) -> PokerAIProfile {
        switch style {
        case .rock: return PokerAIProfile(tightness: 0.08, aggression: 0.30, bluffRate: 0.02, stickiness: 0.0)
        case .shark: return PokerAIProfile(tightness: 0.03, aggression: 0.65, bluffRate: 0.08, stickiness: 0.02)
        case .maniac: return PokerAIProfile(tightness: -0.07, aggression: 0.85, bluffRate: 0.22, stickiness: 0.04)
        case .station: return PokerAIProfile(tightness: -0.04, aggression: 0.15, bluffRate: 0.03, stickiness: 0.12)
        }
    }
}

public enum PokerAI {
    /// Schätzt die Gewinnwahrscheinlichkeit per Monte-Carlo-Simulation gegen
    /// zufällige gegnerische Hände (aus den unbekannten Karten).
    public static func estimateEquity(hole: [Card], community: [Card], opponents: Int,
                                      iterations: Int = 250, random: RandomSource) -> Double {
        let opponents = max(1, opponents)
        let known = Set((hole + community).map { CardKey($0) })
        let unknown = Card.standardDeck().filter { !known.contains(CardKey($0)) }
        var score = 0.0

        for _ in 0..<iterations {
            var pool = unknown
            // Partielles Fisher-Yates: nur so viele Karten mischen, wie benötigt werden.
            let needed = opponents * 2 + (5 - community.count)
            for i in 0..<needed {
                let j = i + random.uniform(pool.count - i)
                pool.swapAt(i, j)
            }
            var cursor = 0
            var board = community
            while board.count < 5 { board.append(pool[cursor]); cursor += 1 }

            let mine = HandEvaluator.bestHand(hole + board)
            var bestOpponent: PokerHandRank?
            for _ in 0..<opponents {
                let theirs = HandEvaluator.bestHand([pool[cursor], pool[cursor + 1]] + board)
                cursor += 2
                if bestOpponent == nil || bestOpponent! < theirs { bestOpponent = theirs }
            }
            if let best = bestOpponent {
                if mine > best { score += 1 }
                else if mine == best { score += 0.5 }
            }
        }
        return score / Double(iterations)
    }

    /// Entscheidung eines KI-Gegners. Zufall wird nur für Spielstil-Variation
    /// (z. B. Bluffs) verwendet – nie, um Karten zu beeinflussen.
    public static func decide(context c: PokerAIContext, style: PokerStyle, random: RandomSource) -> PokerAction {
        let profile = PokerAIProfile.for(style)
        let equity = estimateEquity(hole: c.holeCards, community: c.community,
                                    opponents: c.activeOpponents, random: random)
        let toCall = c.legal.callAmount
        let fairShare = 1.0 / Double(c.activeOpponents + 1)
        // Equity relativ zum fairen Anteil (1.0 = durchschnittlich)
        let strength = equity / fairShare - profile.tightness * 4

        func raise(potFraction: Double) -> PokerAction {
            guard c.legal.canRaise else { return toCall > 0 ? .call : .check }
            let base = max(c.currentBet, 0)
            let size = Int((Double(c.pot + toCall) * potFraction).rounded())
            var target = max(c.legal.minRaiseTo, base + size)
            // Auf Big-Blind-Vielfache runden – wirkt natürlicher
            target = max(c.legal.minRaiseTo, (target / c.bigBlind) * c.bigBlind)
            if target >= c.legal.maxRaiseTo || Double(target) > Double(c.legal.maxRaiseTo) * 0.8 {
                return .allIn
            }
            return .raise(to: target)
        }

        if toCall == 0 {
            if strength > 1.5 && random.chance(profile.aggression) {
                return raise(potFraction: strength > 2.2 ? 0.9 : 0.6)
            }
            if strength < 0.9 && random.chance(profile.bluffRate) {
                return raise(potFraction: 0.5)
            }
            return .check
        }

        let potOdds = Double(toCall) / Double(c.pot + toCall)
        let requiredEquity = potOdds + profile.tightness - profile.stickiness

        if equity > requiredEquity + 0.22 && strength > 1.6 && random.chance(profile.aggression) {
            return raise(potFraction: strength > 2.4 ? 1.0 : 0.7)
        }
        if equity >= requiredEquity {
            return .call
        }
        if random.chance(profile.bluffRate * 0.4) {
            return raise(potFraction: 0.6)
        }
        // Sehr kleiner Nachschuss (z. B. Small Blind komplettieren) wird oft gecallt
        if Double(toCall) <= Double(c.bigBlind) * 0.5 && equity > fairShare * 0.6 {
            return .call
        }
        return .fold
    }
}

/// Schlüssel für eine Karte unabhängig vom Deck-Index.
private struct CardKey: Hashable {
    let rank: Rank
    let suit: Suit
    init(_ card: Card) { rank = card.rank; suit = card.suit }
}
