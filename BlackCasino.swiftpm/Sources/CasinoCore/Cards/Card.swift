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

/// Kartenstapel mit einem oder mehreren Decks.
/// Gemischt wird mit Fisher-Yates über die zentrale `RandomSource`.
public struct Shoe {
    public let deckCount: Int
    public private(set) var cards: [Card] = []
    public private(set) var shuffleCount = 0

    public init(deckCount: Int, random: RandomSource) {
        precondition(deckCount >= 1)
        self.deckCount = deckCount
        reshuffle(random: random)
    }

    public var totalCards: Int { deckCount * 52 }
    public var remaining: Int { cards.count }

    /// Legt alle Karten zurück und mischt vollständig neu.
    public mutating func reshuffle(random: RandomSource) {
        cards = (0..<deckCount).flatMap { Card.standardDeck(deckIndex: $0) }
        random.shuffle(&cards)
        shuffleCount += 1
    }

    /// Zieht die oberste Karte. Innerhalb einer Blackjack-Runde kann ein Deck rechnerisch nicht
    /// leer werden (max. 5 Hände à höchstens 31 Punkte < 340 Punkte im Deck). Als reine
    /// Absicherung gegen Abstürze wird bei leerem Stapel neu gemischt.
    public mutating func draw(random: RandomSource) -> Card {
        if cards.isEmpty { reshuffle(random: random) }
        return cards.removeLast()
    }

    /// Nur für Tests: Karten in genau dieser Ziehreihenfolge bereitlegen.
    mutating func setOrderForTesting(_ drawOrder: [Card]) {
        cards = drawOrder.reversed()
    }
}
