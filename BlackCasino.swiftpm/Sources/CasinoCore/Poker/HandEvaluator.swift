import Foundation

public enum HandCategory: Int, Comparable, Codable, CaseIterable {
    case highCard, onePair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush

    public static func < (lhs: HandCategory, rhs: HandCategory) -> Bool { lhs.rawValue < rhs.rawValue }

    public var name: String {
        switch self {
        case .highCard: return "High Card"
        case .onePair: return "Ein Paar"
        case .twoPair: return "Zwei Paare"
        case .threeOfAKind: return "Drilling"
        case .straight: return "Straße"
        case .flush: return "Flush"
        case .fullHouse: return "Full House"
        case .fourOfAKind: return "Vierling"
        case .straightFlush: return "Straight Flush"
        }
    }
}

/// Vergleichbare Bewertung einer 5-Karten-Hand: zuerst Kategorie, dann Tiebreaker
/// (absteigende Ränge nach Wichtigkeit).
public struct PokerHandRank: Comparable, CustomStringConvertible {
    public let category: HandCategory
    public let tiebreakers: [Int]
    public let cards: [Card]

    public static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        if lhs.category != rhs.category { return lhs.category < rhs.category }
        for (l, r) in zip(lhs.tiebreakers, rhs.tiebreakers) where l != r { return l < r }
        return false
    }

    public static func == (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        lhs.category == rhs.category && lhs.tiebreakers == rhs.tiebreakers
    }

    public var name: String {
        if category == .straightFlush && tiebreakers.first == Rank.ace.rawValue { return "Royal Flush" }
        return category.name
    }

    public var description: String { "\(name) \(cards)" }
}

public enum HandEvaluator {
    /// Beste 5-Karten-Hand aus 5–7 Karten (alle Kombinationen werden geprüft).
    public static func bestHand(_ cards: [Card]) -> PokerHandRank {
        precondition(cards.count >= 5 && cards.count <= 7, "5 bis 7 Karten erwartet")
        if cards.count == 5 { return evaluate5(cards) }
        var best: PokerHandRank?
        let n = cards.count
        for a in 0..<n - 4 {
            for b in a + 1..<n - 3 {
                for c in b + 1..<n - 2 {
                    for d in c + 1..<n - 1 {
                        for e in d + 1..<n {
                            let rank = evaluate5([cards[a], cards[b], cards[c], cards[d], cards[e]])
                            if best == nil || best! < rank { best = rank }
                        }
                    }
                }
            }
        }
        return best!
    }

    public static func evaluate5(_ cards: [Card]) -> PokerHandRank {
        precondition(cards.count == 5)
        let sorted = cards.sorted { $0.rank > $1.rank }
        let ranks = sorted.map { $0.rank.rawValue }
        let isFlush = Set(cards.map(\.suit)).count == 1

        // Straße (inkl. Wheel A-2-3-4-5)
        var straightHigh: Int?
        let unique = Array(Set(ranks)).sorted(by: >)
        if unique.count == 5 {
            if unique[0] - unique[4] == 4 {
                straightHigh = unique[0]
            } else if unique == [14, 5, 4, 3, 2] {
                straightHigh = 5
            }
        }

        // Gruppen nach Häufigkeit, dann Rang
        var counts: [Int: Int] = [:]
        for r in ranks { counts[r, default: 0] += 1 }
        let groups = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key > rhs.key
        }
        let groupRanks = groups.map(\.key)
        let pattern = groups.map(\.value)

        // Karten für die Anzeige in Wertungsreihenfolge sortieren
        let ordered = sorted.sorted { lhs, rhs in
            let lc = counts[lhs.rank.rawValue]!, rc = counts[rhs.rank.rawValue]!
            return lc != rc ? lc > rc : lhs.rank > rhs.rank
        }

        if let high = straightHigh, isFlush {
            return PokerHandRank(category: .straightFlush, tiebreakers: [high], cards: ordered)
        }
        if pattern == [4, 1] {
            return PokerHandRank(category: .fourOfAKind, tiebreakers: groupRanks, cards: ordered)
        }
        if pattern == [3, 2] {
            return PokerHandRank(category: .fullHouse, tiebreakers: groupRanks, cards: ordered)
        }
        if isFlush {
            return PokerHandRank(category: .flush, tiebreakers: ranks, cards: sorted)
        }
        if let high = straightHigh {
            return PokerHandRank(category: .straight, tiebreakers: [high], cards: sorted)
        }
        if pattern == [3, 1, 1] {
            return PokerHandRank(category: .threeOfAKind, tiebreakers: groupRanks, cards: ordered)
        }
        if pattern == [2, 2, 1] {
            return PokerHandRank(category: .twoPair, tiebreakers: groupRanks, cards: ordered)
        }
        if pattern == [2, 1, 1, 1] {
            return PokerHandRank(category: .onePair, tiebreakers: groupRanks, cards: ordered)
        }
        return PokerHandRank(category: .highCard, tiebreakers: ranks, cards: sorted)
    }
}
