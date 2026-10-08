import type { Card } from '../cards';

/** Handkategorie, aufsteigend vergleichbar (wie `HandCategory.rawValue`). */
export type HandCategory = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;

export const HandCategory = {
  highCard: 0, onePair: 1, twoPair: 2, threeOfAKind: 3, straight: 4,
  flush: 5, fullHouse: 6, fourOfAKind: 7, straightFlush: 8,
} as const satisfies Record<string, HandCategory>;

export const ALL_HAND_CATEGORIES: readonly HandCategory[] = [0, 1, 2, 3, 4, 5, 6, 7, 8];

export function handCategoryName(category: HandCategory): string {
  switch (category) {
    case 0: return 'High Card';
    case 1: return 'Ein Paar';
    case 2: return 'Zwei Paare';
    case 3: return 'Drilling';
    case 4: return 'Straße';
    case 5: return 'Flush';
    case 6: return 'Full House';
    case 7: return 'Vierling';
    case 8: return 'Straight Flush';
  }
}

/**
 * Vergleichbare Bewertung einer 5-Karten-Hand: zuerst Kategorie, dann Tiebreaker
 * (absteigende Ränge nach Wichtigkeit).
 */
export class PokerHandRank {
  readonly category: HandCategory;
  readonly tiebreakers: readonly number[];
  /** Die fünf Karten in Wertungsreihenfolge. */
  readonly cards: readonly Card[];

  constructor(category: HandCategory, tiebreakers: readonly number[], cards: readonly Card[]) {
    this.category = category;
    this.tiebreakers = Object.freeze([...tiebreakers]);
    this.cards = Object.freeze([...cards]);
  }

  /** < 0, wenn a schwächer ist; 0 bei Gleichstand; > 0, wenn a stärker ist. */
  static compare(a: PokerHandRank, b: PokerHandRank): number {
    if (a.category !== b.category) return a.category - b.category;
    const n = Math.min(a.tiebreakers.length, b.tiebreakers.length);
    for (let i = 0; i < n; i++) {
      if (a.tiebreakers[i] !== b.tiebreakers[i]) return a.tiebreakers[i]! - b.tiebreakers[i]!;
    }
    return 0;
  }

  /** Gleichwertig (Kategorie und Tiebreaker; die konkreten Karten zählen nicht). */
  equals(other: PokerHandRank): boolean {
    return this.category === other.category
      && this.tiebreakers.length === other.tiebreakers.length
      && this.tiebreakers.every((t, i) => t === other.tiebreakers[i]);
  }

  lessThan(other: PokerHandRank): boolean { return PokerHandRank.compare(this, other) < 0; }
  greaterThan(other: PokerHandRank): boolean { return PokerHandRank.compare(this, other) > 0; }

  get name(): string {
    if (this.category === 8 && this.tiebreakers[0] === 14) return 'Royal Flush';
    return handCategoryName(this.category);
  }

  get description(): string {
    return `${this.name} [${this.cards.map((c) => c.description).join(', ')}]`;
  }
}

const POW15 = [1, 15, 225, 3375, 50625, 759375];

/**
 * Schnelle numerische Bewertung (Kategorie + Tiebreaker als eine Zahl). Ordnung identisch zu
 * `PokerHandRank.compare`; intern genutzt, um aus 7 Karten die beste Kombination zu finden.
 */
function score5(c0: Card, c1: Card, c2: Card, c3: Card, c4: Card): number {
  const r = [c0.rank, c1.rank, c2.rank, c3.rank, c4.rank] as number[];
  // absteigend sortieren (Insertion Sort, 5 Elemente)
  for (let i = 1; i < 5; i++) {
    const v = r[i]!;
    let j = i - 1;
    while (j >= 0 && r[j]! < v) { r[j + 1] = r[j]!; j--; }
    r[j + 1] = v;
  }
  const isFlush = c0.suit === c1.suit && c0.suit === c2.suit && c0.suit === c3.suit && c0.suit === c4.suit;
  const distinct = r[0] !== r[1] && r[1] !== r[2] && r[2] !== r[3] && r[3] !== r[4];
  let straightHigh = 0;
  if (distinct) {
    if (r[0]! - r[4]! === 4) straightHigh = r[0]!;
    else if (r[0] === 14 && r[1] === 5 && r[2] === 4 && r[3] === 3 && r[4] === 2) straightHigh = 5;
  }
  const enc = (cat: number, tb: number[]): number => {
    let s = cat * POW15[5]!;
    for (let i = 0; i < tb.length; i++) s += tb[i]! * POW15[4 - i]!;
    return s;
  };
  if (straightHigh && isFlush) return enc(8, [straightHigh]);
  // Gruppen (Häufigkeit absteigend, dann Rang absteigend)
  const groups: [number, number][] = []; // [rank, count]
  for (let i = 0; i < 5;) {
    let j = i;
    while (j < 5 && r[j] === r[i]) j++;
    groups.push([r[i]!, j - i]);
    i = j;
  }
  groups.sort((a, b) => (a[1] !== b[1] ? b[1] - a[1] : b[0] - a[0]));
  const gr = groups.map((g) => g[0]);
  const p0 = groups[0]![1];
  const p1 = groups[1]?.[1] ?? 0;
  if (p0 === 4) return enc(7, gr);
  if (p0 === 3 && p1 === 2) return enc(6, gr);
  if (isFlush) return enc(5, r);
  if (straightHigh) return enc(4, [straightHigh]);
  if (p0 === 3) return enc(3, gr);
  if (p0 === 2 && p1 === 2) return enc(2, gr);
  if (p0 === 2) return enc(1, gr);
  return enc(0, r);
}

function bestHandIndices(cards: readonly Card[]): { score: number; combo: Card[] } {
  const n = cards.length;
  let bestScore = -1;
  let best: Card[] = [];
  for (let a = 0; a < n - 4; a++) {
    for (let b = a + 1; b < n - 3; b++) {
      for (let c = b + 1; c < n - 2; c++) {
        for (let d = c + 1; d < n - 1; d++) {
          for (let e = d + 1; e < n; e++) {
            const s = score5(cards[a]!, cards[b]!, cards[c]!, cards[d]!, cards[e]!);
            if (s > bestScore) {
              bestScore = s;
              best = [cards[a]!, cards[b]!, cards[c]!, cards[d]!, cards[e]!];
            }
          }
        }
      }
    }
  }
  return { score: bestScore, combo: best };
}

/** Numerischer Wert der besten 5-Karten-Hand (gleiche Ordnung wie `PokerHandRank`). Intern/KI. */
export function bestHandScore(cards: readonly Card[]): number {
  return bestHandIndices(cards).score;
}

function evaluate5(cards: readonly Card[]): PokerHandRank {
  if (cards.length !== 5) throw new RangeError('5 Karten erwartet');
  const sorted = [...cards].sort((x, y) => y.rank - x.rank);
  const ranks = sorted.map((c) => c.rank as number);
  const isFlush = new Set(cards.map((c) => c.suit)).size === 1;

  // Straße (inkl. Wheel A-2-3-4-5)
  let straightHigh: number | null = null;
  const unique = [...new Set(ranks)].sort((x, y) => y - x);
  if (unique.length === 5) {
    if (unique[0]! - unique[4]! === 4) straightHigh = unique[0]!;
    else if (unique.join(',') === '14,5,4,3,2') straightHigh = 5;
  }

  // Gruppen nach Häufigkeit, dann Rang
  const counts = new Map<number, number>();
  for (const r of ranks) counts.set(r, (counts.get(r) ?? 0) + 1);
  const groups = [...counts.entries()].sort((l, r) => (l[1] !== r[1] ? r[1] - l[1] : r[0] - l[0]));
  const groupRanks = groups.map((g) => g[0]);
  const pattern = groups.map((g) => g[1]).join(',');

  // Karten für die Anzeige in Wertungsreihenfolge sortieren
  const ordered = [...sorted].sort((l, r) => {
    const lc = counts.get(l.rank)!;
    const rc = counts.get(r.rank)!;
    return lc !== rc ? rc - lc : r.rank - l.rank;
  });

  if (straightHigh !== null && isFlush) return new PokerHandRank(8, [straightHigh], ordered);
  if (pattern === '4,1') return new PokerHandRank(7, groupRanks, ordered);
  if (pattern === '3,2') return new PokerHandRank(6, groupRanks, ordered);
  if (isFlush) return new PokerHandRank(5, ranks, sorted);
  if (straightHigh !== null) return new PokerHandRank(4, [straightHigh], sorted);
  if (pattern === '3,1,1') return new PokerHandRank(3, groupRanks, ordered);
  if (pattern === '2,2,1') return new PokerHandRank(2, groupRanks, ordered);
  if (pattern === '2,1,1,1') return new PokerHandRank(1, groupRanks, ordered);
  return new PokerHandRank(0, ranks, sorted);
}

export const HandEvaluator = {
  /** Beste 5-Karten-Hand aus 5–7 Karten (alle Kombinationen werden geprüft). */
  bestHand(cards: readonly Card[]): PokerHandRank {
    if (cards.length < 5 || cards.length > 7) throw new RangeError('5 bis 7 Karten erwartet');
    if (cards.length === 5) return evaluate5(cards);
    // Erste Kombination mit maximaler Wertung – wie in Swift (`best < rank`).
    return evaluate5(bestHandIndices(cards).combo);
  },
  evaluate5,
};
