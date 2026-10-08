import { describe, expect, it } from 'vitest';
import {
  type BlackjackAction, BlackjackBot, BlackjackError, BlackjackHand, BlackjackTableEngine, HandValue, SeededRandomSource,
} from '../src/core';
import { c, sortedActions } from './helpers';

describe('BlackjackTableEngine', () => {
  it('three seats play independently against one dealer', () => {
    const table = new BlackjackTableEngine({ random: new SeededRandomSource(1) });
    // Runde 1: S1, S2, S3, Dealer offen · Runde 2: S1, S2, S3, Dealer verdeckt · danach Aktionen
    table.testOnlyDeckForNextRound = [
      c(10), c(5), c(6), c(9, 'hearts'),
      c(6, 'hearts'), c(5, 'hearts'), c(5, 'clubs'), c(7, 'hearts'),
      c(9, 'clubs'), // S1 Hit → 25 Bust
      c(10, 'diamonds'), // S3 Double → 21
      c(2, 'diamonds'), // Dealer 16 → 18
    ];
    table.startRound([{ seatID: 1, bet: 100 }, { seatID: 2, bet: 50 }, { seatID: 3, bet: 20 }]);
    expect(table.currentSeatID).toBe(1);
    try {
      table.perform('stand', 2);
      expect.unreachable('Nicht am Zug');
    } catch (e) {
      expect((e as BlackjackError).kind).toBe('notYourTurn');
    }
    expect(table.availableActions(2).size).toBe(0);

    table.perform('hit', 1); // Spieler 1: Hit
    expect(table.currentSeatID).toBe(2);
    table.perform('stand', 2); // Spieler 2: Stand
    expect(table.currentSeatID).toBe(3);
    expect(table.additionalStake('double', 3)).toBe(20);
    const events = table.perform('double', 3); // Spieler 3: Double

    expect(table.phase).toBe('settled');
    expect(HandValue.of(table.dealerCards).total).toBe(18);
    expect(table.seat(1)?.results[0]?.outcome).toBe('bust');
    expect(table.seat(2)?.results[0]?.outcome).toBe('lose'); // 10 vs 18
    expect(table.seat(3)?.results[0]?.outcome).toBe('win'); // 21 vs 18
    expect(table.seat(3)?.results[0]?.payout).toBe(80);
    const settled = events.find((e) => e.type === 'settled');
    expect(settled && settled.type === 'settled' ? settled.seatResults.map((s) => [s.seatID, s.stake, s.payout]) : null)
      .toEqual([[1, 100, 0], [2, 50, 0], [3, 40, 80]]);
  });

  it('seats are isolated from other seats actions', () => {
    // Gleicher Kartenstapel; nur die Aktion von Platz 1 unterscheidet sich.
    const run = (seat1Action: BlackjackAction) => {
      const table = new BlackjackTableEngine({ random: new SeededRandomSource(3) });
      table.testOnlyDeckForNextRound = [c(10), c(9), c(6, 'hearts'), c(7, 'hearts'), c(8), c(10, 'clubs'),
        c(2, 'clubs'), c(3, 'clubs'), c(4, 'clubs')];
      table.startRound([{ seatID: 1, bet: 10 }, { seatID: 2, bet: 10 }]);
      table.perform(seat1Action, 1);
      return table.seat(2)!.hands[0]!.cards.map((x) => x.id);
    };
    expect(run('stand')).toEqual(run('stand'));
    expect(run('hit').slice(0, 2)).toEqual(run('stand').slice(0, 2));
  });

  it('standAll and invalid bets', () => {
    const table = new BlackjackTableEngine({ random: new SeededRandomSource(4) });
    expect(() => table.startRound([])).toThrow(BlackjackError);
    expect(() => table.startRound([{ seatID: 1, bet: 10 }, { seatID: 1, bet: 10 }])).toThrow(BlackjackError);
    expect(() => table.startRound([{ seatID: 1, bet: 1 }])).toThrow(BlackjackError);
    table.testOnlyDeckForNextRound = [c(10), c(9), c(6, 'hearts'), c(7, 'hearts'), c(8), c(8, 'clubs')];
    table.startRound([{ seatID: 1, bet: 10 }, { seatID: 2, bet: 10 }]);
    table.standAll(1);
    expect(table.currentSeatID).toBe(2);
    table.standAll(2);
    expect(table.phase).toBe('settled');
  });

  it('many multi-seat rounds have no duplicate cards', () => {
    const random = new SeededRandomSource(9);
    const table = new BlackjackTableEngine({ random });
    for (let i = 0; i < 3_000; i++) {
      table.startRound([1, 2, 3, 4, 5].map((seatID) => ({ seatID, bet: 10 })));
      while (table.phase === 'playerTurn' && table.currentSeatID !== null) {
        const seat = table.currentSeatID;
        table.perform(random.pick(sortedActions(table.availableActions(seat)))!, seat);
      }
      const all = [...table.seats.flatMap((s) => s.hands.flatMap((h) => h.cards)), ...table.dealerCards];
      expect(new Set(all.map((x) => x.id)).size).toBe(all.length);
      expect(table.seats.map((s) => s.results.length)).toEqual(table.seats.map((s) => s.hands.length));
    }
  }, 30_000);

  it('bot uses only visible information', () => {
    const hand = new BlackjackHand({ id: 0, cards: [c(10), c(6)], bet: 10 });
    expect(BlackjackBot.decide(hand, c(5), new Set<BlackjackAction>(['hit', 'stand', 'double']))).toBe('stand');
    expect(BlackjackBot.decide(hand, c(10), new Set<BlackjackAction>(['hit', 'stand', 'double']))).toBe('hit');
    const eleven = new BlackjackHand({ id: 0, cards: [c(6), c(5)], bet: 10 });
    expect(BlackjackBot.decide(eleven, c(9), new Set<BlackjackAction>(['hit', 'stand', 'double']))).toBe('double');
    const aces = new BlackjackHand({ id: 0, cards: [c(14), c(14, 'hearts')], bet: 10 });
    expect(BlackjackBot.decide(aces, c(9), new Set<BlackjackAction>(['hit', 'stand', 'double', 'split']))).toBe('split');
  });

  it('bot always returns an available action in random play', () => {
    const random = new SeededRandomSource(17);
    const table = new BlackjackTableEngine({ random });
    for (let i = 0; i < 2_000; i++) {
      table.startRound([{ seatID: 1, bet: 10 }, { seatID: 2, bet: 10 }]);
      while (table.phase === 'playerTurn' && table.currentSeatID !== null) {
        const seat = table.currentSeatID;
        const available = table.availableActions(seat);
        const action = BlackjackBot.decide(table.currentHand!, table.dealerCards[0]!, available);
        expect(available.has(action)).toBe(true);
        table.perform(action, seat);
      }
    }
  });
});
