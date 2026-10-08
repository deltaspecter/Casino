import { describe, expect, it } from 'vitest';
import {
  BlackjackEngine, Card, HoldemEngine, makeBlackjackRules, makeCard, PlayerProfile, PokerSeat, SeededRandomSource,
  SlotCatalog, SlotMachine, SystemRandomSource,
} from '../src/core';
import { chiSquare } from './helpers';

/**
 * Prüft die Zufallslogik: korrektes Mischen, keine Dubletten, Vielfalt
 * und vor allem Unabhängigkeit von Kontostand, Einsatz, Verlauf, Missionen und Erfolgen.
 */
describe('RNG fairness', () => {
  it('shuffle is uniform over all positions', () => {
    // Position des Pik-Ass in 52.000 Mischungen: Chi² mit 51 Freiheitsgraden (99,9 %-Grenze ≈ 87)
    const random = new SeededRandomSource(101);
    const counts = new Array<number>(52).fill(0);
    const target = makeCard(14, 'spades');
    for (let i = 0; i < 52_000; i++) {
      const deck = Card.standardDeck();
      random.shuffle(deck);
      counts[deck.findIndex((x) => x.id === target.id)]! += 1;
    }
    expect(chiSquare(counts)).toBeLessThan(87);
  });

  it('system RNG shuffle is uniform over all positions', () => {
    const random = new SystemRandomSource();
    const counts = new Array<number>(52).fill(0);
    for (let i = 0; i < 52_000; i++) {
      const deck = Card.standardDeck();
      random.shuffle(deck);
      counts[deck.findIndex((x) => x.id === 51)]! += 1;
    }
    // Echter Zufall: großzügige Schranke (Fehlalarm-Wahrscheinlichkeit ~1e-6)
    expect(chiSquare(counts)).toBeLessThan(110);
  });

  it('uniform has no modulo bias (non power of two bound)', () => {
    const random = new SeededRandomSource(202);
    const counts = new Array<number>(7).fill(0);
    for (let i = 0; i < 70_000; i++) counts[random.uniform(7)]! += 1;
    // 6 Freiheitsgrade, 99,9 %-Grenze ≈ 22,5
    expect(chiSquare(counts)).toBeLessThan(22.5);
  });

  it('shuffle keeps every card exactly once', () => {
    const random = new SystemRandomSource();
    const reference = Card.standardDeck().map((x) => x.id).sort((a, b) => a - b);
    for (let i = 0; i < 1_000; i++) {
      const deck = Card.standardDeck();
      random.shuffle(deck);
      expect(deck.length).toBe(52);
      expect(deck.map((x) => x.id).sort((a, b) => a - b)).toEqual(reference);
    }
  });

  it('different results occur', () => {
    const random = new SystemRandomSource();
    const orders = new Set<string>();
    for (let i = 0; i < 500; i++) {
      const deck = Card.standardDeck();
      random.shuffle(deck);
      orders.add(deck.map((x) => x.id).join(','));
    }
    expect(orders.size, 'Mischungen wiederholen sich nicht').toBe(500);

    const machine = new SlotMachine(SlotCatalog.crimsonSevens);
    const stops = new Set(Array.from({ length: 500 }, () => machine.spin(1, random).stops.join(',')));
    expect(stops.size).toBeGreaterThan(450);
  });

  it('slot reel stops are uniform', () => {
    const def = SlotCatalog.dragonFortune;
    const machine = new SlotMachine(def);
    const random = new SeededRandomSource(31);
    const counts = def.reelStrips.map((s) => new Array<number>(s.length).fill(0));
    for (let i = 0; i < 66_000; i++) {
      const r = machine.spin(1, random);
      r.stops.forEach((stop, reel) => { counts[reel]![stop]! += 1; });
    }
    for (const reel of counts) {
      // Streifenlänge 31 → 30 Freiheitsgrade, 99,9 %-Grenze ≈ 59,7 (Swift-Test: < 62)
      expect(chiSquare(reel)).toBeLessThan(62);
    }
  });

  /** Die Gewinnwahrscheinlichkeit nach einem Gewinn entspricht der nach einem Verlust. */
  it('slot outcome independent of previous outcome', () => {
    const machine = new SlotMachine(SlotCatalog.crimsonSevens);
    const random = new SeededRandomSource(44);
    const afterWin = { wins: 0, total: 0 };
    const afterLoss = { wins: 0, total: 0 };
    let previousWin = false;
    for (let i = 0; i < 300_000; i++) {
      const win = machine.spin(1, random).isWin;
      const bucket = previousWin ? afterWin : afterLoss;
      bucket.total += 1;
      if (win) bucket.wins += 1;
      previousWin = win;
    }
    expect(Math.abs(afterWin.wins / afterWin.total - afterLoss.wins / afterLoss.total)).toBeLessThanOrEqual(0.01);
  }, 30_000);

  it('blackjack outcome independent of previous outcome', () => {
    const engine = new BlackjackEngine({ random: new SeededRandomSource(45) });
    const afterWin = { wins: 0, total: 0 };
    const afterLoss = { wins: 0, total: 0 };
    let previousNet = 0;
    for (let i = 0; i < 60_000; i++) {
      engine.startRound(10);
      while (engine.phase === 'playerTurn') engine.perform(engine.activeHand!.value.total >= 17 ? 'stand' : 'hit');
      const net = engine.results.reduce((s, r) => s + r.net, 0);
      if (previousNet > 0) { afterWin.total += 1; if (net > 0) afterWin.wins += 1; }
      else if (previousNet < 0) { afterLoss.total += 1; if (net > 0) afterLoss.wins += 1; }
      previousNet = net;
    }
    expect(Math.abs(afterWin.wins / afterWin.total - afterLoss.wins / afterLoss.total)).toBeLessThanOrEqual(0.02);
  }, 60_000);

  /** Einsatzhöhe (und damit Kontostand) hat keinen Einfluss auf die Karten. */
  it('blackjack cards independent of stake', () => {
    const run = (bet: number): number[][] => {
      const engine = new BlackjackEngine({
        rules: makeBlackjackRules({ minBet: 1, maxBet: 1_000_000 }), random: new SeededRandomSource(77),
      });
      const rounds: number[][] = [];
      for (let i = 0; i < 500; i++) {
        engine.startRound(bet);
        while (engine.phase === 'playerTurn') engine.perform(engine.activeHand!.value.total >= 17 ? 'stand' : 'hit');
        rounds.push([...engine.hands.flatMap((h) => h.cards), ...engine.dealerCards].map((x) => x.id));
      }
      return rounds;
    };
    expect(run(1)).toEqual(run(999_999));
  });

  it('slot results independent of stake', () => {
    const machine = new SlotMachine(SlotCatalog.midnightGems);
    const a = new SeededRandomSource(8);
    const b = new SeededRandomSource(8);
    for (let i = 0; i < 2_000; i++) {
      expect(machine.spin(1, a).stops).toEqual(machine.spin(100, b).stops);
    }
  });

  it('poker deal independent of stacks', () => {
    const deal = (stacks: number[]): number[] => {
      const seats = stacks.map((stack, i) => new PokerSeat({ id: i, name: 'P', isHuman: false, style: 'rock', stack }));
      const engine = new HoldemEngine({ seats, smallBlind: 5, bigBlind: 10, random: new SeededRandomSource(3) });
      engine.startHand();
      return engine.seats.flatMap((s) => s.holeCards).map((x) => x.id);
    };
    expect(deal([20, 20, 20])).toEqual(deal([1_000_000, 50, 999]));
  });

  /**
   * Missionen, Erfolge, Daily Reward und Statistik greifen nicht auf die Spiel-Zufallsquelle zu:
   * Eine Spin-Folge bleibt identisch, egal was dazwischen im Profil passiert.
   */
  it('profile activity does not touch game RNG', () => {
    const machine = new SlotMachine(SlotCatalog.crimsonSevens);
    const plain = new SeededRandomSource(55);
    const busy = new SeededRandomSource(55);
    const missionRandom = new SeededRandomSource(999); // eigene Quelle wie in der App
    const profile = new PlayerProfile();
    const now = Date.now();
    for (let i = 0; i < 1_000; i++) {
      const expected = machine.spin(1, plain);
      profile.refreshDailyMissions(new Date(now + i * 3_600_000), missionRandom);
      try { profile.claimDailyReward(new Date(now + i * 86_400_000)); } catch { /* bereits abgeholt */ }
      for (const m of profile.dailyMissions) { try { profile.claimMission(m.missionID); } catch { /* offen */ } }
      for (const a of [...profile.unlockedAchievements]) { try { profile.claimAchievement(a); } catch { /* schon */ } }
      const actual = machine.spin(1, busy);
      expect(actual).toEqual(expected);
      profile.record({ type: 'slotSpin', bet: actual.totalBet, payout: actual.totalPayout });
    }
  });

  it('system random source range and spread', () => {
    const random = new SystemRandomSource();
    const seen = new Set<number>();
    for (let i = 0; i < 2_000; i++) {
      const v = random.uniform(7);
      expect(v >= 0 && v < 7).toBe(true);
      seen.add(v);
    }
    expect(seen.size).toBe(7);
  });
});
