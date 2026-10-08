import { describe, expect, it } from 'vitest';
import { ALL_RANKS, Card, SeededRandomSource, Shoe, SystemRandomSource, shuffle } from '../src/core';

/** Referenz-Implementierung (BigInt) von SplitMix64 + Swift `next(upperBound:)` zum Abgleich. */
class ReferenceSplitMix {
  private state: bigint;
  constructor(seed: bigint) { this.state = seed; }
  next(): bigint {
    const M = (1n << 64n) - 1n;
    this.state = (this.state + 0x9E3779B97F4A7C15n) & M;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & M;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & M;
    return z ^ (z >> 31n);
  }
  uniform(n: number): number {
    const ub = BigInt(n);
    const M = (1n << 64n) - 1n;
    let m = this.next() * ub;
    if ((m & M) < ub) {
      const t = ((1n << 64n) - ub) % ub;
      while ((m & M) < t) m = this.next() * ub;
    }
    return Number(m >> 64n);
  }
}

describe('Cards & Random', () => {
  it('SplitMix64 is bit-identical to the reference algorithm (and Swift)', () => {
    // Bekannte Referenzwerte für SplitMix64 mit Seed 0
    const r0 = new SeededRandomSource(0);
    expect(r0.next()).toBe(0xE220A8397B1DCDAFn);
    expect(r0.next()).toBe(0x6E789E6AA1B965F4n);

    for (const seed of [1n, 42n, 0xFFFF_FFFF_FFFF_FFFFn, 123456789012345n]) {
      const fast = new SeededRandomSource(seed);
      const ref = new ReferenceSplitMix(seed);
      for (let i = 0; i < 2_000; i++) expect(fast.next()).toBe(ref.next());
    }
  });

  it('uniform matches Swift Lemire algorithm exactly', () => {
    const fast = new SeededRandomSource(7);
    const ref = new ReferenceSplitMix(7n);
    const bounds = [1, 2, 3, 7, 13, 31, 33, 52, 1000, 2 ** 31 - 1, 0xFFFF_FFFF, 3_000_000_019];
    for (let i = 0; i < 5_000; i++) {
      const n = bounds[i % bounds.length]!;
      expect(fast.uniform(n)).toBe(ref.uniform(n));
    }
  });

  it('uniform rejects invalid bounds', () => {
    const r = new SeededRandomSource(1);
    expect(() => r.uniform(0)).toThrow();
    expect(() => r.uniform(-3)).toThrow();
    expect(() => r.uniform(2.5)).toThrow();
  });

  it('unitDouble is in [0, 1) and chance works', () => {
    const r = new SeededRandomSource(11);
    let hits = 0;
    for (let i = 0; i < 20_000; i++) {
      const d = r.unitDouble();
      expect(d).toBeGreaterThanOrEqual(0);
      expect(d).toBeLessThan(1);
      if (r.chance(0.3)) hits += 1;
    }
    expect(hits / 20_000).toBeCloseTo(0.3, 1);
    expect(new SeededRandomSource(1).chance(0)).toBe(false);
    expect(new SeededRandomSource(1).chance(1)).toBe(true);
  });

  it('pick returns null for empty arrays', () => {
    const r = new SeededRandomSource(1);
    expect(r.pick([])).toBeNull();
    expect([1, 2, 3]).toContain(r.pick([1, 2, 3]));
  });

  it('shoe contains every card exactly once per deck', () => {
    const shoe = new Shoe(6, new SeededRandomSource(1));
    expect(shoe.remaining).toBe(312);
    expect(new Set(shoe.cards.map((c) => c.id)).size).toBe(312);
    for (const rank of ALL_RANKS) {
      expect(shoe.cards.filter((c) => c.rank === rank).length).toBe(24);
    }
  });

  it('shoe draws without duplicates', () => {
    const random = new SeededRandomSource(2);
    const shoe = new Shoe(1, random);
    const drawn = Array.from({ length: 52 }, () => shoe.draw(random));
    expect(new Set(drawn.map((c) => c.id)).size).toBe(52);
    expect(shoe.remaining).toBe(0);
  });

  it('shuffle is uniform enough', () => {
    // Jede Position eines 4er-Arrays sollte jedes Element ~25 % der Zeit enthalten.
    const random = new SeededRandomSource(3);
    const counts = Array.from({ length: 4 }, () => [0, 0, 0, 0]);
    const trials = 40_000;
    for (let t = 0; t < trials; t++) {
      const a = [0, 1, 2, 3];
      random.shuffle(a);
      a.forEach((v, pos) => { counts[pos]![v]! += 1; });
    }
    for (const row of counts) {
      for (const n of row) expect(Math.abs(n / trials - 0.25)).toBeLessThan(0.01);
    }
  });

  it('free shuffle function equals method', () => {
    const a = Card.standardDeck();
    const b = Card.standardDeck();
    shuffle(a, new SeededRandomSource(5));
    new SeededRandomSource(5).shuffle(b);
    expect(a.map((c) => c.id)).toEqual(b.map((c) => c.id));
  });

  it('system random source produces values in range', () => {
    const random = new SystemRandomSource();
    for (let i = 0; i < 1_000; i++) {
      const v = random.uniform(7);
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(7);
    }
  });

  it('card ids and descriptions match Swift', () => {
    const deck = Card.standardDeck(1);
    expect(deck[0]!.id).toBe(52);
    expect(deck[0]!.description).toBe('2♣');
    expect(Card.make(14, 'spades').id).toBe(3 * 13 + 12);
    expect(Card.make(10, 'hearts').description).toBe('10♥');
    expect(Card.make(12, 'diamonds').description).toBe('Q♦');
  });
});
