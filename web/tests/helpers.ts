import { ALL_RANKS, type Card, makeCard, type Rank, rankLabel, type Suit } from '../src/core';

/** Karte bauen (Standard: Pik), wie `c(.ten)` in den Swift-Tests. */
export function c(rank: Rank, suit: Suit = 'spades'): Card {
  return makeCard(rank, suit);
}

/** Format: "As Kd 10h 2c" */
export function cards(s: string): Card[] {
  const suits: Record<string, Suit> = { c: 'clubs', d: 'diamonds', h: 'hearts', s: 'spades' };
  return s.split(' ').filter(Boolean).map((token) => {
    const suit = suits[token.slice(-1)]!;
    const rank = ALL_RANKS.find((r) => rankLabel(r) === token.slice(0, -1))!;
    return makeCard(rank, suit);
  });
}

/** Chi-Quadrat-Statistik für beobachtete Häufigkeiten bei Gleichverteilung. */
export function chiSquare(counts: number[]): number {
  const total = counts.reduce((a, b) => a + b, 0);
  const expected = total / counts.length;
  return counts.reduce((acc, x) => acc + (x - expected) ** 2 / expected, 0);
}

export function sortedActions<T extends string>(set: Set<T>): T[] {
  return [...set].sort();
}
