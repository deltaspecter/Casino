import Foundation

public struct HandValue: Equatable {
    public let total: Int
    /// `true`, wenn ein Ass als 11 gezählt wird.
    public let isSoft: Bool

    /// Bewertet beliebige Blackjack-Karten: Asse zählen 11, solange die Hand dadurch nicht überkauft.
    public static func of(_ cards: [Card]) -> HandValue {
        var total = 0
        var softAces = 0
        for card in cards {
            total += card.rank.blackjackValue
            if card.rank == .ace { softAces += 1 }
        }
        while total > 21 && softAces > 0 {
            total -= 10
            softAces -= 1
        }
        return HandValue(total: total, isSoft: softAces > 0)
    }

    public var display: String {
        isSoft && total < 21 ? "\(total - 10)/\(total)" : "\(total)"
    }
}

public struct BlackjackHand: Identifiable, Equatable {
    public let id: Int
    public internal(set) var cards: [Card]
    public internal(set) var bet: Int
    public internal(set) var isDoubled = false
    public internal(set) var isStood = false
    /// Entstand durch Split – ein 21 aus zwei Karten zählt dann nicht als Blackjack.
    public let isFromSplit: Bool
    public let isSplitAces: Bool

    public init(id: Int, cards: [Card], bet: Int, isFromSplit: Bool = false, isSplitAces: Bool = false) {
        self.id = id
        self.cards = cards
        self.bet = bet
        self.isFromSplit = isFromSplit
        self.isSplitAces = isSplitAces
    }

    public var value: HandValue { HandValue.of(cards) }
    public var isBust: Bool { value.total > 21 }
    public var isBlackjack: Bool { !isFromSplit && cards.count == 2 && value.total == 21 }

    /// Hand ist fertig gespielt.
    public var isFinished: Bool {
        isStood || isBust || isDoubled || value.total == 21 || (isSplitAces && cards.count >= 2)
    }
}

public enum HandOutcome: String, Codable, Equatable {
    case blackjack, win, push, lose, bust

    public var title: String {
        switch self {
        case .blackjack: return "BLACKJACK"
        case .win: return "GEWONNEN"
        case .push: return "PUSH"
        case .lose: return "VERLOREN"
        case .bust: return "BUST"
        }
    }
}

public struct HandResult: Equatable {
    public let handID: Int
    public let outcome: HandOutcome
    public let stake: Int
    /// Gesamte Rückzahlung inklusive Einsatz (0 bei Verlust).
    public let payout: Int
    public var net: Int { payout - stake }
}
