import type { RandomSource } from './random';

// MARK: - Suit

export type Suit = 'clubs' | 'diamonds' | 'hearts' | 'spades';

/** Wie die Swift-Enum-Fälle: `Suit.clubs` usw. */
export const Suit = {
  clubs: 'clubs',
  diamonds: 'diamonds',
  hearts: 'hearts',
  spades: 'spades',
} as const satisfies Record<Suit, Suit>;

/** `Suit.allCases` in Swift-Reihenfolge (rawValue 0…3). */
export const ALL_SUITS: readonly Suit[] = ['clubs', 'diamonds', 'hearts', 'spades'];

export function suitRawValue(suit: Suit): number {
  return ALL_SUITS.indexOf(suit);
}

export function suitSymbol(suit: Suit): string {
  switch (suit) {
    case 'clubs': return '♣';
    case 'diamonds': return '♦';
    case 'hearts': return '♥';
    case 'spades': return '♠';
  }
}

export function suitIsRed(suit: Suit): boolean {
  return suit === 'diamonds' || suit === 'hearts';
}

// MARK: - Rank

/** Rang als Zahl wie `Rank.rawValue` in Swift (2 … 14, Ass = 14). Vergleichbar mit `<`. */
export type Rank = 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14;

export const Rank = {
  two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  jack: 11, queen: 12, king: 13, ace: 14,
} as const satisfies Record<string, Rank>;

/** `Rank.allCases` aufsteigend. */
export const ALL_RANKS: readonly Rank[] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];

export function rankLabel(rank: Rank): string {
  switch (rank) {
    case 11: return 'J';
    case 12: return 'Q';
    case 13: return 'K';
    case 14: return 'A';
    default: return String(rank);
  }
}

/** Wert im Blackjack (Ass zunächst als 11, wird bei der Handbewertung ggf. auf 1 reduziert). */
export function rankBlackjackValue(rank: Rank): number {
  if (rank === 14) return 11;
  if (rank >= 11) return 10;
  return rank;
}

// MARK: - Card

/**
 * Eine Spielkarte (unveränderliches Wertobjekt). `deckIndex` unterscheidet identische Karten
 * aus verschiedenen Decks eines Mehrfach-Schlittens (Shoe).
 * `id` und `description` sind wie in Swift abgeleitet und werden beim Erzeugen gesetzt.
 */
export interface Card {
  readonly rank: Rank;
  readonly suit: Suit;
  readonly deckIndex: number;
  /** deckIndex * 52 + suit.rawValue * 13 + (rank - 2) */
  readonly id: number;
  /** z. B. "A♠", "10♥" */
  readonly description: string;
}

export function makeCard(rank: Rank, suit: Suit, deckIndex = 0): Card {
  return Object.freeze({
    rank,
    suit,
    deckIndex,
    id: deckIndex * 52 + suitRawValue(suit) * 13 + (rank - 2),
    description: rankLabel(rank) + suitSymbol(suit),
  });
}

/** Swift-ähnlicher Namensraum: `Card.make(...)`, `Card.standardDeck()`. */
export const Card = {
  make: makeCard,
  /** Vollständiges, sortiertes 52-Karten-Deck. */
  standardDeck(deckIndex = 0): Card[] {
    const cards: Card[] = [];
    for (const suit of ALL_SUITS) {
      for (const rank of ALL_RANKS) cards.push(makeCard(rank, suit, deckIndex));
    }
    return cards;
  },
  /** Gleichheit wie in Swift (alle Felder). */
  equals(a: Card, b: Card): boolean {
    return a.rank === b.rank && a.suit === b.suit && a.deckIndex === b.deckIndex;
  },
};

// MARK: - Shoe

/**
 * Kartenstapel mit einem oder mehreren Decks.
 * Gemischt wird mit Fisher-Yates über die zentrale `RandomSource`.
 */
export class Shoe {
  readonly deckCount: number;
  private _cards: Card[] = [];
  private _shuffleCount = 0;

  constructor(deckCount: number, random: RandomSource) {
    if (!(deckCount >= 1)) throw new RangeError('deckCount >= 1');
    this.deckCount = deckCount;
    this.reshuffle(random);
  }

  /** Restliche Karten; die nächste gezogene Karte ist die letzte im Array. */
  get cards(): readonly Card[] { return this._cards; }
  get shuffleCount(): number { return this._shuffleCount; }
  get totalCards(): number { return this.deckCount * 52; }
  get remaining(): number { return this._cards.length; }

  /** Legt alle Karten zurück und mischt vollständig neu. */
  reshuffle(random: RandomSource): void {
    const cards: Card[] = [];
    for (let d = 0; d < this.deckCount; d++) cards.push(...Card.standardDeck(d));
    random.shuffle(cards);
    this._cards = cards;
    this._shuffleCount += 1;
  }

  /**
   * Zieht die oberste Karte. Innerhalb einer Blackjack-Runde kann ein Deck rechnerisch nicht
   * leer werden. Als reine Absicherung wird bei leerem Stapel neu gemischt.
   */
  draw(random: RandomSource): Card {
    if (this._cards.length === 0) this.reshuffle(random);
    return this._cards.pop()!;
  }

  /** NUR FÜR TESTS: Karten in genau dieser Ziehreihenfolge bereitlegen. */
  testOnlySetDrawOrder(drawOrder: readonly Card[]): void {
    this._cards = [...drawOrder].reverse();
  }
}
