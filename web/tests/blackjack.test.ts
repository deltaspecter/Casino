import { describe, expect, it } from 'vitest';
import {
  type BlackjackAction, BlackjackEngine, BlackjackError, BlackjackHand, type Card, HandValue, SeededRandomSource,
  DEFAULT_BLACKJACK_RULES, handOutcomeTitle,
} from '../src/core';
import { c, sortedActions } from './helpers';

/**
 * Spielt eine Runde mit fest vorgegebener Ziehreihenfolge
 * (Spieler, Dealer offen, Spieler, Dealer verdeckt, danach weitere Karten).
 */
function scenario(deck: Card[], actions: BlackjackAction[] = [], bet = 100): BlackjackEngine {
  const engine = new BlackjackEngine({ random: new SeededRandomSource(1) });
  engine.testOnlyDeckForNextRound = deck;
  engine.startRound(bet);
  for (const action of actions) {
    expect(engine.phase, `Aktion ${action} ohne Spielerzug`).toBe('playerTurn');
    engine.perform(action);
  }
  expect(engine.phase).toBe('settled');
  return engine;
}

const hv = (total: number, isSoft: boolean) => ({ total, isSoft });

describe('Blackjack', () => {
  it('has the documented default rules', () => {
    expect(DEFAULT_BLACKJACK_RULES).toEqual({
      deckCount: 1, dealerHitsSoft17: false, doubleAfterSplit: true, maxHands: 4, resplitAces: false, minBet: 10, maxBet: 5_000,
    });
    expect(handOutcomeTitle('win')).toBe('GEWONNEN');
    expect(handOutcomeTitle('lose')).toBe('VERLOREN');
  });

  // MARK: - Handbewertung

  it('hand values', () => {
    expect(HandValue.of([c(14), c(13)])).toEqual(hv(21, true));
    expect(HandValue.of([c(14), c(14), c(9)])).toEqual(hv(21, true));
    expect(HandValue.of([c(14), c(14), c(14)])).toEqual(hv(13, true));
    expect(HandValue.of([c(14), c(6), c(13)])).toEqual(hv(17, false));
    expect(HandValue.of([c(13), c(12), c(2)])).toEqual(hv(22, false));
    expect(HandValue.display(HandValue.of([c(14), c(6)]))).toBe('7/17');
    expect(HandValue.of([c(14), c(14), c(14), c(14), c(7)])).toEqual(hv(21, true));
  });

  it('split twenty-one is not blackjack', () => {
    expect(new BlackjackHand({ id: 0, cards: [c(14), c(13)], bet: 10, isFromSplit: true }).isBlackjack).toBe(false);
    expect(new BlackjackHand({ id: 0, cards: [c(14), c(13)], bet: 10 }).isBlackjack).toBe(true);
    expect(new BlackjackHand({ id: 0, cards: [c(7), c(7), c(7)], bet: 10 }).isBlackjack).toBe(false);
  });

  it('rejects invalid bets and actions', () => {
    const engine = new BlackjackEngine({ random: new SeededRandomSource(1) });
    expect(() => engine.startRound(1)).toThrow(BlackjackError);
    expect(() => engine.startRound(1_000_000)).toThrow(BlackjackError);
    expect(() => engine.perform('hit')).toThrow(BlackjackError); // keine Runde aktiv
    engine.testOnlyDeckForNextRound = [c(10), c(7), c(8), c(10)];
    engine.startRound(10);
    try {
      engine.perform('split'); // kein Paar
      expect.unreachable();
    } catch (e) {
      expect((e as BlackjackError).kind).toBe('illegalAction');
      expect((e as BlackjackError).action).toBe('split');
    }
    expect(() => engine.startRound(10)).toThrow(BlackjackError); // Runde läuft noch
  });

  // MARK: - Regelszenarien

  it('player blackjack pays 3:2', () => {
    const e = scenario([c(14), c(9, 'hearts'), c(13), c(7, 'clubs')]);
    expect(e.results[0]?.outcome).toBe('blackjack');
    expect(e.results[0]?.payout).toBe(250);
    expect(e.dealerCards.length, 'Dealer zieht nach Spieler-Blackjack nicht').toBe(2);
  });

  it('dealer blackjack beats player', () => {
    const e = scenario([c(9), c(14, 'hearts'), c(9, 'clubs'), c(13, 'hearts')]);
    expect(e.results[0]?.outcome).toBe('lose');
    expect(e.results[0]?.payout).toBe(0);
    expect(e.isHoleCardRevealed).toBe(true);
  });

  it('both blackjack is push', () => {
    const e = scenario([c(14), c(14, 'hearts'), c(13), c(12, 'hearts')]);
    expect(e.results[0]?.outcome).toBe('push');
    expect(e.results[0]?.payout).toBe(100);
  });

  it('player bust', () => {
    const e = scenario([c(10), c(7, 'hearts'), c(6), c(10, 'hearts'), c(9)], ['hit']);
    expect(e.results[0]?.outcome).toBe('bust');
    expect(e.results[0]?.payout).toBe(0);
    expect(e.dealerCards.length, 'Bei überkaufter Spielerhand zieht der Dealer nicht').toBe(2);
  });

  it('push', () => {
    const e = scenario([c(10), c(10, 'hearts'), c(8), c(8, 'hearts')], ['stand']);
    expect(e.results[0]?.outcome).toBe('push');
    expect(e.results[0]?.payout).toBe(100);
    expect(e.results[0]?.net).toBe(0);
  });

  it('dealer bust', () => {
    const e = scenario([c(10), c(10, 'hearts'), c(8), c(6, 'hearts'), c(13, 'clubs')], ['stand']);
    expect(HandValue.of(e.dealerCards).total).toBe(26);
    expect(e.results[0]?.outcome).toBe('win');
    expect(e.results[0]?.payout).toBe(200);
  });

  it('dealer stands on soft 17', () => {
    const e = scenario([c(10), c(14, 'hearts'), c(9), c(6, 'hearts'), c(5, 'clubs')], ['stand']);
    expect(e.dealerCards.length).toBe(2);
    expect(HandValue.of(e.dealerCards)).toEqual(hv(17, true));
    expect(e.results[0]?.outcome).toBe('win');
  });

  it('dealer hits sixteen and soft hands resolve correctly', () => {
    // Spieler: A+5 (soft 16) → Hit 4 → soft 20. Dealer: 10+6 → zieht 5 → 21.
    const e = scenario([c(14), c(10, 'hearts'), c(5), c(6, 'hearts'), c(4), c(5, 'clubs')], ['hit', 'stand']);
    expect(e.hands[0]!.value).toEqual(hv(20, true));
    expect(HandValue.of(e.dealerCards).total).toBe(21);
    expect(e.results[0]?.outcome).toBe('lose');
  });

  it('double down', () => {
    const e = scenario([c(5), c(9, 'hearts'), c(6), c(7, 'hearts'), c(13), c(2, 'clubs')], ['double']);
    expect(e.hands[0]!.cards.length, 'Nach Double genau eine Karte').toBe(3);
    expect(e.hands[0]!.bet).toBe(200);
    expect(e.results[0]?.outcome).toBe('win');
    expect(e.results[0]?.payout).toBe(400);
  });

  it('split', () => {
    const e = scenario([c(8), c(10, 'hearts'), c(8, 'clubs'), c(7, 'hearts'), c(3), c(10, 'clubs')], ['split', 'stand', 'stand']);
    expect(e.hands.length).toBe(2);
    expect(e.hands.map((h) => h.value.total)).toEqual([11, 18]);
    expect(e.results.map((r) => r.outcome)).toEqual(['lose', 'win']);
    expect(e.totalStake).toBe(200);
  });

  it('split aces get one card and twenty-one is not blackjack', () => {
    const e = scenario([c(14), c(9, 'hearts'), c(14, 'clubs'), c(7, 'hearts'), c(13), c(5), c(5, 'hearts')], ['split']);
    expect(e.hands.map((h) => h.cards.length)).toEqual([2, 2]);
    expect(HandValue.of(e.dealerCards).total).toBe(21);
    expect(e.results.map((r) => r.outcome), '21 aus geteilten Assen ist kein Blackjack').toEqual(['push', 'lose']);
  });

  it('double after split', () => {
    const e = scenario([c(9), c(6, 'hearts'), c(9, 'clubs'), c(10, 'hearts'), c(2), c(14), c(8), c(13, 'clubs')],
      ['split', 'double', 'stand']);
    // Hand 1: 9+2 → Double → 8 = 19 · Hand 2: 9+A = 20 · Dealer 16 → K = Bust
    expect(e.hands[0]!.bet).toBe(200);
    expect(e.results.map((r) => r.outcome)).toEqual(['win', 'win']);
    expect(e.results.reduce((s, r) => s + r.payout, 0)).toBe(600);
  });

  it('emits events and additional stake', () => {
    const engine = new BlackjackEngine({ random: new SeededRandomSource(1) });
    engine.testOnlyDeckForNextRound = [c(8), c(10, 'hearts'), c(8, 'clubs'), c(7, 'hearts'), c(3), c(10, 'clubs')];
    const start = engine.startRound(50);
    expect(start.map((e) => e.type)).toEqual([
      'shuffled', 'dealtToPlayer', 'dealtToDealer', 'dealtToPlayer', 'dealtToDealer', 'activeHandChanged',
    ]);
    expect(start[4]).toMatchObject({ type: 'dealtToDealer', faceDown: true });
    expect(engine.dealerVisibleValue.total).toBe(10);
    expect(engine.additionalStake('split')).toBe(50);
    expect(engine.additionalStake('hit')).toBe(0);
    expect(sortedActions(engine.availableActions())).toEqual(['double', 'hit', 'split', 'stand']);
    const ev = engine.perform('split');
    expect(ev[0]).toMatchObject({ type: 'split', originalHandID: 0, newHandID: 1 });
    expect(engine.activeHandIndex).toBe(0);
  });

  it('hands are replaced, not mutated', () => {
    const engine = new BlackjackEngine({ random: new SeededRandomSource(1) });
    engine.testOnlyDeckForNextRound = [c(5), c(9, 'hearts'), c(6), c(7, 'hearts'), c(2), c(13, 'clubs'), c(13)];
    engine.startRound(10);
    const before = engine.hands[0]!;
    engine.perform('hit');
    expect(before.cards.length).toBe(2);
    expect(engine.hands[0]!.cards.length).toBe(3);
  });

  // MARK: - Zufallsrunden

  it('no duplicate cards within a round', () => {
    const random = new SeededRandomSource(5);
    const engine = new BlackjackEngine({ random });
    for (let i = 0; i < 5_000; i++) {
      engine.startRound(10);
      while (engine.phase === 'playerTurn') {
        engine.perform(random.pick(sortedActions(engine.availableActions()))!);
      }
      const all = [...engine.hands.flatMap((h) => h.cards), ...engine.dealerCards];
      expect(new Set(all.map((x) => x.id)).size).toBe(all.length);
      expect(engine.shoe.remaining).toBe(52 - all.length);
    }
  });

  it('many random rounds keep invariants', () => {
    const random = new SeededRandomSource(42);
    const engine = new BlackjackEngine({ random });
    let totalStake = 0;
    let totalPayout = 0;

    for (let i = 0; i < 20_000; i++) {
      engine.startRound(100);
      while (engine.phase === 'playerTurn') {
        const actions = sortedActions(engine.availableActions());
        expect(actions.length).toBeGreaterThan(0);
        engine.perform(random.pick(actions)!);
      }
      expect(engine.phase).toBe('settled');
      expect(engine.isHoleCardRevealed).toBe(true);
      expect(engine.results.length).toBe(engine.hands.length);
      expect(engine.hands.length).toBeLessThanOrEqual(engine.rules.maxHands);

      const dealer = HandValue.of(engine.dealerCards);
      const endedImmediately = (engine.dealerCards.length === 2 && dealer.total === 21)
        || (engine.hands.length === 1 && engine.hands[0]!.isBlackjack);
      if (engine.hands.some((h) => !h.isBust) && !endedImmediately) {
        expect(dealer.total).toBeGreaterThanOrEqual(17);
        if (engine.dealerCards.length > 2) {
          expect(HandValue.of(engine.dealerCards.slice(0, -1)).total).toBeLessThan(17);
        }
      }
      engine.hands.forEach((hand, k) => {
        const result = engine.results[k]!;
        expect(hand.bet).toBe(result.stake);
        switch (result.outcome) {
          case 'blackjack': expect(result.payout).toBe(Math.floor((hand.bet * 5) / 2)); break;
          case 'win': expect(result.payout).toBe(hand.bet * 2); break;
          case 'push': expect(result.payout).toBe(hand.bet); break;
          case 'lose':
          case 'bust': expect(result.payout).toBe(0); break;
        }
        expect(result.payout).toBeGreaterThanOrEqual(0);
        totalStake += result.stake;
        totalPayout += result.payout;
      });
    }
    const rtp = totalPayout / totalStake;
    expect(rtp).toBeGreaterThan(0.5);
    expect(rtp).toBeLessThan(1.0);
  }, 60_000);

  it('simple strategy return is realistic', () => {
    // Stehen ab 17, sonst ziehen: langfristig ca. 92–97 %.
    const engine = new BlackjackEngine({ random: new SeededRandomSource(7) });
    let stake = 0;
    let payout = 0;
    for (let i = 0; i < 50_000; i++) {
      engine.startRound(10);
      while (engine.phase === 'playerTurn') {
        engine.perform(engine.activeHand!.value.total >= 17 ? 'stand' : 'hit');
      }
      stake += engine.results.reduce((s, r) => s + r.stake, 0);
      payout += engine.results.reduce((s, r) => s + r.payout, 0);
    }
    const rtp = payout / stake;
    expect(rtp).toBeGreaterThan(0.90);
    expect(rtp).toBeLessThan(1.0);
  }, 60_000);

  it('consecutive rounds are freshly shuffled', () => {
    const engine = new BlackjackEngine({ random: new SeededRandomSource(9) });
    let shuffles = engine.shoe.shuffleCount;
    for (let i = 0; i < 50; i++) {
      engine.startRound(10);
      expect(engine.shoe.shuffleCount, 'Jede Runde beginnt mit neu gemischtem Deck').toBe(shuffles + 1);
      shuffles = engine.shoe.shuffleCount;
      while (engine.phase === 'playerTurn') engine.perform('stand');
    }
  });
});
