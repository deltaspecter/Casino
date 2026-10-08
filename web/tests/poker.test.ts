import { describe, expect, it } from 'vitest';
import {
  ALL_POKER_STYLES, type Card, HandEvaluator, HoldemEngine, PokerAction, PokerAI, PokerAIContext, PokerError,
  PokerHandRank, PokerSeat, SeededRandomSource,
} from '../src/core';
import { cards } from './helpers';

const best = (s: string): PokerHandRank => HandEvaluator.bestHand(cards(s));
const e5 = (s: string): PokerHandRank => HandEvaluator.evaluate5(cards(s));
const ids = (cs: readonly Card[]): number[] => cs.map((x) => x.id);

function makeEngine(stacks: number[], seed = 1): HoldemEngine {
  const seats = stacks.map((stack, i) => new PokerSeat({
    id: i, name: `P${i}`, isHuman: i === 0, style: i === 0 ? null : ALL_POKER_STYLES[i % 4]!, stack,
  }));
  return new HoldemEngine({ seats, smallBlind: 5, bigBlind: 10, random: new SeededRandomSource(seed) });
}

/** Ziehreihenfolge: Hole Cards reihum ab links vom Button (zwei Runden), dann Burn + Flop, Burn + Turn, Burn + River. */
function deck(holeRound1: string[], holeRound2: string[], board: string[]): Card[] {
  const burn = cards('2c 2d 2h'); // Burn-Karten spielen keine Rolle
  const b = board.flatMap((x) => cards(x));
  return [
    ...holeRound1.flatMap((x) => cards(x)), ...holeRound2.flatMap((x) => cards(x)),
    burn[0]!, ...b.slice(0, 3), burn[1]!, b[3]!, burn[2]!, b[4]!,
  ];
}

function allInEveryone(engine: HoldemEngine): void {
  while (engine.isHandInProgress && engine.currentIndex !== null) {
    const idx = engine.currentIndex;
    const legal = engine.legalActions(idx)!;
    engine.apply(legal.canRaise ? PokerAction.allIn : PokerAction.call, idx);
  }
}

function expectPokerError(fn: () => unknown, kind: PokerError['kind']): void {
  try {
    fn();
    expect.unreachable();
  } catch (e) {
    expect(e).toBeInstanceOf(PokerError);
    expect((e as PokerError).kind).toBe(kind);
  }
}

describe('Poker hand evaluation', () => {
  it('all categories', () => {
    expect(best('As Ks Qs Js 10s 2d 3c').name).toBe('Royal Flush');
    expect(best('9h 8h 7h 6h 5h Kd Kc').category).toBe(8);
    expect(best('5s 4s 3s 2s As Kd Kc').category).toBe(8);
    expect(best('9s 9d 9h 9c 2s 3d 4c').category).toBe(7);
    expect(best('9s 9d 9h 2c 2s 3d 4c').category).toBe(6);
    expect(best('As 9s 7s 4s 2s 3d 4c').category).toBe(5);
    expect(best('As 2d 3h 4c 5s Kd Qc').category).toBe(4);
    expect(best('10s Jd Qh Kc As 2d 2c').category).toBe(4);
    expect(best('7s 7d 7h Kc 2s 3d 9c').category).toBe(3);
    expect(best('7s 7d Kh Kc 2s 3d 9c').category).toBe(2);
    expect(best('7s 7d Ah Kc 2s 3d 9c').category).toBe(1);
    expect(best('7s 8d Ah Kc 2s 3d 10c').category).toBe(0);
    expect(best('7s 7d Ah Kc 2s 3d 9c').name).toBe('Ein Paar');
    expect(best('9s 9d 9h 9c 2s 3d 4c').name).toBe('Vierling');
  });

  it('category order is official ranking', () => {
    const ascending = [
      '7s 8d Ah Kc 2s', '7s 7d Ah Kc 2s', '7s 7d Kh Kc 2s', '7s 7d 7h Kc 2s', '6s 7d 8h 9c 10s',
      '2h 7h 9h Jh Kh', '7s 7d 7h Kc Ks', '7s 7d 7h 7c Ks', '5d 6d 7d 8d 9d', '10c Jc Qc Kc Ac',
    ].map(e5);
    for (let i = 0; i + 1 < ascending.length; i++) {
      expect(ascending[i]!.lessThan(ascending[i + 1]!), `${ascending[i]!.name} < ${ascending[i + 1]!.name}`).toBe(true);
    }
    expect(ascending.at(-1)!.name).toBe('Royal Flush');
  });

  it('tiebreakers', () => {
    expect(e5('As 2d 3h 4c 5s').lessThan(e5('2s 3d 4h 5c 6s')), 'Wheel ist die niedrigste Straße').toBe(true);
    expect(e5('As Ad Kh 4c 3s').greaterThan(e5('Ac Ah Qh 4d 3d')), 'Kicker entscheidet').toBe(true);
    expect(e5('Ks Kd 2h 2c As').greaterThan(e5('Qs Qd Jh Jc As')), 'Höheres oberes Paar').toBe(true);
    expect(e5('Ks Kd 3h 3c 2s').greaterThan(e5('Kh Kc 2h 2d As')), 'Zweites Paar vor Kicker').toBe(true);
    expect(e5('3s 3d 3h 2c 2s').greaterThan(e5('2s 2d 2h Ac As')), 'Full House: Drilling zählt zuerst').toBe(true);
    expect(e5('Ah 9h 7h 4h 3h').greaterThan(e5('Ad 9d 7d 4d 2d')), 'Flush: alle Karten vergleichen').toBe(true);
    expect(e5('As Kd Qh Jc 9s').equals(e5('Ad Ks Qc Jh 9d')), 'Gleiche Werte → Gleichstand').toBe(true);
    expect(e5('9s 9d 9h 9c As').greaterThan(e5('9s 9d 9h 9c Ks')), 'Vierling-Kicker').toBe(true);
  });

  it('best hand matches brute force over evaluate5 for random 7-card hands', () => {
    const random = new SeededRandomSource(123);
    for (let t = 0; t < 300; t++) {
      const d = cards('2c 3c 4c 5c 6c 7c 8c 9c 10c Jc Qc Kc Ac 2d 3d 4d 5d 6d 7d 8d 9d 10d Jd Qd Kd Ad 2h 3h 4h 5h 6h 7h 8h 9h 10h Jh Qh Kh Ah 2s 3s 4s 5s 6s 7s 8s 9s 10s Js Qs Ks As');
      random.shuffle(d);
      const seven = d.slice(0, 7);
      let brute: PokerHandRank | null = null;
      for (let a = 0; a < 7; a++) for (let b = a + 1; b < 7; b++) {
        const five = seven.filter((_, i) => i !== a && i !== b);
        const r = HandEvaluator.evaluate5(five);
        if (!brute || brute.lessThan(r)) brute = r;
      }
      const fast = HandEvaluator.bestHand(seven);
      expect(fast.equals(brute!)).toBe(true);
    }
  });

  it('display cards are in ranking order', () => {
    expect(e5('2s Kd 2h Kc 2c').cards.map((x) => x.rank)).toEqual([2, 2, 2, 13, 13]);
    expect(e5('As 2d 3h 4c 5s').tiebreakers).toEqual([5]);
  });
});

describe('HoldemEngine', () => {
  it('split pot on board straight', () => {
    // Heads-up, Button = Sitz 0. Ausgabe: Sitz 1, Sitz 0, Sitz 1, Sitz 0
    const engine = makeEngine([100, 100]);
    engine.testOnlySetButtonIndex(1);
    engine.testOnlyDeckForNextHand = deck(['3h', '4h'], ['3s', '4s'], ['As', 'Kd', 'Qc', 'Jh', '10s']);
    engine.startHand();
    expect(engine.seats[engine.buttonIndex]!.id).toBe(0);
    allInEveryone(engine);
    expect(engine.lastShowdown.length).toBe(2);
    expect(engine.lastShowdown[0]!.hand.equals(engine.lastShowdown[1]!.hand)).toBe(true);
    expect(engine.seats.map((s) => s.stack), 'Gleichstand → Pot wird geteilt').toEqual([100, 100]);
  });

  it('kicker decides showdown', () => {
    const engine = makeEngine([100, 100]);
    engine.testOnlySetButtonIndex(1);
    // Sitz 1: A♦ Q♣ · Sitz 0: A♣ K♦
    engine.testOnlyDeckForNextHand = deck(['Ad', 'Ac'], ['Qc', 'Kd'], ['Ah', '7s', '4d', '2s', '9h']);
    engine.startHand();
    allInEveryone(engine);
    expect(engine.seats.map((s) => s.stack)).toEqual([200, 0]);
    expect(engine.lastAwards[0]?.handName).toBe('Ein Paar');
  });

  it('side pots', () => {
    // Button = Sitz 0, SB = Sitz 1, BB = Sitz 2. Ausgabe beginnt bei Sitz 1.
    const engine = makeEngine([50, 200, 200]);
    engine.testOnlySetButtonIndex(2);
    engine.testOnlyDeckForNextHand = deck(['Kh', 'Qh', 'Ah'], ['Kd', 'Qd', 'Ad'], ['2s', '5d', '8h', '9s', 'Jc']);
    engine.startHand();
    allInEveryone(engine);
    // Hauptpot 150 → Sitz 0 (Asse), Side-Pot 300 → Sitz 1 (Könige)
    expect(engine.seats.map((s) => s.stack)).toEqual([150, 300, 0]);
    expect(new Set(engine.lastAwards.map((a) => a.potIndex))).toEqual(new Set([0, 1]));
    expect(engine.lastAwards).toEqual([
      { seatID: 0, amount: 150, potIndex: 0, handName: 'Ein Paar' },
      { seatID: 1, amount: 300, potIndex: 1, handName: 'Ein Paar' },
    ]);
  });

  it('buildPots splits contributions into main and side pots', () => {
    const engine = makeEngine([50, 200, 200]);
    engine.testOnlySetButtonIndex(2);
    engine.testOnlyDeckForNextHand = deck(['Kh', 'Qh', 'Ah'], ['Kd', 'Qd', 'Ad'], ['2s', '5d', '8h', '9s', 'Jc']);
    engine.startHand();
    // Sitz 0 geht all-in (50), Sitz 1 callt, Sitz 2 callt → noch kein Showdown
    engine.apply(PokerAction.allIn, 0);
    engine.apply(PokerAction.raise(150), 1);
    engine.apply(PokerAction.call, 2);
    expect(engine.street).toBe('flop');
    const pots = engine.buildPots();
    expect(pots.map((p) => p.amount)).toEqual([150, 200]);
    expect(pots.map((p) => [...p.eligible])).toEqual([[0, 1, 2], [1, 2]]);
  });

  it('fold wins uncontested', () => {
    const engine = makeEngine([100, 100]);
    engine.testOnlySetButtonIndex(1);
    engine.startHand();
    const first = engine.currentIndex!;
    const events = engine.apply(PokerAction.fold, first);
    expect(engine.isHandInProgress).toBe(false);
    expect(engine.lastShowdown.length, 'Ohne Showdown werden keine Karten gezeigt').toBe(0);
    expect(engine.seats.reduce((s, x) => s + x.stack, 0)).toBe(200);
    expect(engine.seats[first]!.stack, 'Small Blind verloren').toBe(95);
    expect(events.map((e) => e.type)).toEqual(['action', 'betsCollected', 'potAwarded', 'handFinished']);
    expect(engine.lastAwards[0]!.handName).toBeNull();
  });

  it('betting order and min raise', () => {
    // 3 Spieler: Button 0, SB 1, BB 2 → preflop handelt zuerst Sitz 0, postflop Sitz 1.
    const engine = makeEngine([1_000, 1_000, 1_000]);
    engine.testOnlySetButtonIndex(2);
    engine.startHand();
    expect(engine.currentIndex).toBe(0);
    const legal = engine.legalActions(0)!;
    expect(legal.canCheck).toBe(false);
    expect(legal.callAmount).toBe(10);
    expect(legal.minRaiseTo).toBe(20);
    expectPokerError(() => engine.apply(PokerAction.raise(15), 0), 'illegalAction'); // Raise unter Mindestbetrag
    expectPokerError(() => engine.apply(PokerAction.check, 0), 'illegalAction'); // Check trotz offenem Einsatz
    expectPokerError(() => engine.apply(PokerAction.call, 1), 'notYourTurn'); // Nicht am Zug
    engine.apply(PokerAction.raise(30), 0);
    expect(engine.legalActions(1)?.minRaiseTo, 'Mindest-Reraise = letzte Erhöhung').toBe(50);
    expect(engine.seats[0]!.lastAction).toEqual({ kind: 'raise', streetTotal: 30 });
    engine.apply(PokerAction.call, 1);
    engine.apply(PokerAction.call, 2);
    expect(engine.street).toBe('flop');
    expect(engine.community.length).toBe(3);
    expect(engine.pot).toBe(90);
    expect(engine.currentIndex, 'Postflop beginnt links vom Button').toBe(1);
    expect(engine.legalActions(1)!.canCheck).toBe(true);
    engine.apply(PokerAction.check, 1);
    engine.apply(PokerAction.raise(40), 2); // Bet
    expect(engine.seats[2]!.lastAction?.kind).toBe('bet');
    expect(engine.collectedPot).toBe(90);
    engine.apply(PokerAction.fold, 0);
    engine.apply(PokerAction.call, 1);
    expect(engine.street).toBe('turn');
    expect(engine.pot).toBe(170);
  });

  it('big blind option preflop', () => {
    const engine = makeEngine([1_000, 1_000, 1_000]);
    engine.testOnlySetButtonIndex(2);
    engine.startHand();
    engine.apply(PokerAction.call, 0);
    engine.apply(PokerAction.call, 1);
    expect(engine.currentIndex, 'Big Blind darf noch handeln').toBe(2);
    expect(engine.legalActions(2)!.canCheck).toBe(true);
    engine.apply(PokerAction.check, 2);
    expect(engine.street).toBe('flop');
  });

  it('blinds, button rotation and heads-up rule', () => {
    const engine = makeEngine([1_000, 1_000, 1_000]);
    engine.testOnlySetButtonIndex(0);
    const events = engine.startHand();
    expect(events[0]).toEqual({ type: 'handStarted', handNumber: 1, buttonSeatID: 1 });
    expect(events[1]).toEqual({ type: 'blindPosted', seatID: 2, amount: 5, isBig: false });
    expect(events[2]).toEqual({ type: 'blindPosted', seatID: 0, amount: 10, isBig: true });
    expect(engine.currentIndex).toBe(1);
    engine.apply(PokerAction.fold, 1);
    engine.apply(PokerAction.fold, 2);
    expect(engine.isHandInProgress).toBe(false);
    expectPokerError(() => engine.apply(PokerAction.fold, 0), 'notYourTurn');
    engine.startHand();
    expect(engine.buttonIndex).toBe(2);

    // Heads-up: Button zahlt Small Blind und handelt preflop zuerst
    const hu = makeEngine([500, 500]);
    hu.testOnlySetButtonIndex(1);
    const ev = hu.startHand();
    expect(hu.buttonIndex).toBe(0);
    expect(ev[1]).toEqual({ type: 'blindPosted', seatID: 0, amount: 5, isBig: false });
    expect(hu.currentIndex).toBe(0);
  });

  it('busted seats sit out and table management only between hands', () => {
    const engine = makeEngine([1_000, 0, 1_000]);
    engine.startHand();
    expect(engine.seats[1]!.isSittingOut).toBe(true);
    expect(engine.seats[1]!.holeCards.length).toBe(0);
    expectPokerError(() => engine.setStack(100, 1), 'handInProgress');
    expectPokerError(() => engine.startHand(), 'handInProgress');
    const empty = makeEngine([1_000, 0, 0]);
    expectPokerError(() => empty.startHand(), 'notEnoughPlayers');
  });

  it('chips are conserved and cards unique over many hands', () => {
    const random = new SeededRandomSource(99);
    const engine = makeEngine([1_000, 400, 1_500, 250, 800, 2_000], 5);
    for (let h = 0; h < 2_000; h++) {
      engine.seats.forEach((s, i) => { if (s.stack === 0) engine.setStack(500, i); });
      const before = engine.seats.reduce((s, x) => s + x.stack, 0);
      engine.startHand();
      const dealt = engine.seats.flatMap((s) => s.holeCards);
      let guardCounter = 0;
      while (engine.isHandInProgress && engine.currentIndex !== null) {
        const idx = engine.currentIndex;
        guardCounter += 1;
        expect(guardCounter, 'Hand endet nicht').toBeLessThan(500);
        const legal = engine.legalActions(idx)!;
        const options: PokerAction[] = [PokerAction.fold, PokerAction.allIn];
        options.push(legal.canCheck ? PokerAction.check : PokerAction.call);
        if (legal.canRaise) options.push(PokerAction.raise(legal.minRaiseTo));
        engine.apply(random.pick(options)!, idx);
      }
      const all = [...dealt, ...engine.community];
      expect(new Set(all.map((x) => x.id)).size, 'Karte doppelt ausgegeben').toBe(all.length);
      expect(engine.seats.reduce((s, x) => s + x.stack, 0), 'Chips müssen erhalten bleiben').toBe(before);
      expect(engine.seats.every((s) => s.stack >= 0)).toBe(true);
      if (engine.lastShowdown.length > 0) expect(engine.community.length).toBe(5);
    }
  }, 60_000);

  it('AI produces legal actions and sees no hidden cards', () => {
    const random = new SeededRandomSource(3);
    const engine = makeEngine([1_000, 1_000, 1_000, 1_000], 8);
    for (let h = 0; h < 40; h++) {
      engine.seats.forEach((s, i) => { if (s.stack === 0) engine.setStack(1_000, i); });
      engine.startHand();
      while (engine.isHandInProgress && engine.currentIndex !== null) {
        const idx = engine.currentIndex;
        const ctx = new PokerAIContext(engine, idx);
        expect(ids(ctx.holeCards)).toEqual(ids(engine.seats[idx]!.holeCards));
        expect(ids(ctx.community)).toEqual(ids(engine.community));
        expect(Object.keys(ctx)).not.toContain('deck');
        const action = PokerAI.decide(ctx, engine.seats[idx]!.style ?? 'shark', random);
        expect(() => engine.apply(action, idx), JSON.stringify(action)).not.toThrow();
      }
    }
  }, 60_000);

  it('AI decisions do not change the deal', () => {
    // Gleicher Karten-Seed, völlig unterschiedliche Spielweisen → identische Karten.
    const dealtCards = (policy: (engine: HoldemEngine, idx: number) => PokerAction): number[][] => {
      const engine = makeEngine([5_000, 5_000, 5_000], 21);
      const result: number[][] = [];
      for (let h = 0; h < 30; h++) {
        engine.startHand();
        while (engine.isHandInProgress && engine.currentIndex !== null) {
          const idx = engine.currentIndex;
          engine.apply(policy(engine, idx), idx);
        }
        result.push(ids(engine.seats.flatMap((s) => s.holeCards)));
        engine.seats.forEach((_, i) => engine.setStack(5_000, i));
      }
      return result;
    };
    const passive = dealtCards((engine, idx) => (engine.legalActions(idx)!.canCheck ? PokerAction.check : PokerAction.call));
    const folding = dealtCards(() => PokerAction.fold);
    expect(passive).toEqual(folding);
  });

  it('equity estimate is sensible', () => {
    const random = new SeededRandomSource(4);
    const aces = PokerAI.estimateEquity({ hole: cards('As Ah'), community: [], opponents: 1, iterations: 2_000, random });
    const junk = PokerAI.estimateEquity({ hole: cards('7c 2d'), community: [], opponents: 1, iterations: 2_000, random });
    expect(Math.abs(aces - 0.85)).toBeLessThanOrEqual(0.04);
    expect(Math.abs(junk - 0.35)).toBeLessThanOrEqual(0.05);
  }, 30_000);
});
