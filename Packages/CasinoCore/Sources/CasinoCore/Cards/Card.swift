import Foundation

public enum Suit: Int, CaseIterable, Codable, Hashable {
    case clubs, diamonds, hearts, spades

    public var symbol: String {
        switch self {
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    public var isRed: Bool { self == .diamonds || self == .hearts }
}

public enum Rank: Int, CaseIterable, Codable, Hashable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    /// Wert im Blackjack (Ass zunächst als 11, wird bei der Handbewertung ggf. auf 1 reduziert).
    public var blackjackValue: Int {
        switch self {
        case .ace: return 11
        case .jack, .queen, .king: return 10
        default: return rawValue
        }
    }
}

/// Eine Spielkarte. `deckIndex` unterscheidet identische Karten aus
/// verschiedenen Decks eines Mehrfach-Schlittens (Shoe).
public struct Card: Hashable, Codable, Identifiable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit
    public let deckIndex: Int

    public init(_ rank: Rank, _ suit: Suit, deckIndex: Int = 0) {
        self.rank = rank
        self.suit = suit
        self.deckIndex = deckIndex
    }

    public var id: Int { deckIndex * 52 + suit.rawValue * 13 + (rank.rawValue - 2) }
    public var description: String { rank.label + suit.symbol }

    /// Vollständiges, sortiertes 52-Karten-Deck.
    public static func standardDeck(deckIndex: Int = 0) -> [Card] {
        Suit.allCases.flatMap { suit in Rank.allCases.map { Card($0, suit, deckIndex: deckIndex) } }
    }
}

/// Kartenschlitten mit einem oder mehreren Decks.
/// Gemischt wird mit Fisher-Yates über die zentrale `RandomSource`.
public struct Shoe {
    public let deckCount: Int
    /// Anteil des Schlittens, der ausgespielt wird, bevor neu gemischt wird.
    public let penetration: Double
    public private(set) var cards: [Card] = []
    public private(set) var shuffleCount = 0

    public init(deckCount: Int, penetration: Double = 0.75, random: RandomSource) {
        precondition(deckCount >= 1)
        self.deckCount = deckCount
        self.penetration = min(max(penetration, 0.2), 0.95)
        reshuffle(random: random)
    }

    public var totalCards: Int { deckCount * 52 }
    public var remaining: Int { cards.count }
    public var needsReshuffle: Bool {
        Double(totalCards - remaining) >= Double(totalCards) * penetration
    }

    /// Setzt alle Karten zurück in den Schlitten und mischt vollständig neu.
    public mutating func reshuffle(random: RandomSource) {
        cards = (0..<deckCount).flatMap { Card.standardDeck(deckIndex: $0) }
        random.shuffle(&cards)
        shuffleCount += 1
    }

    /// Zieht die oberste Karte. Ist der Schlitten leer, wird automatisch neu gemischt.
    public mutating func draw(random: RandomSource) -> Card {
        if cards.isEmpty { reshuffle(random: random) }
        return cards.removeLast()
    }
}
