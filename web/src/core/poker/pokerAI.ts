import { Card } from '../cards';
import type { RandomSource } from '../random';
import { bestHandScore } from './handEvaluator';
import type { HoldemEngine } from './holdemEngine';
import { PokerAction, type PokerLegalActions, type PokerStyle } from './types';

/**
 * Alles, was ein KI-Gegner sehen darf: eigene Karten, Board, Pot und Einsätze.
 * Die verdeckten Karten anderer Spieler und die Reihenfolge des Decks sind
 * bewusst **nicht** enthalten – die KI spielt fair.
 */
export class PokerAIContext {
  readonly holeCards: readonly Card[];
  readonly community: readonly Card[];
  readonly pot: number;
  readonly currentBet: number;
  readonly streetBet: number;
  readonly stack: number;
  readonly bigBlind: number;
  readonly activeOpponents: number;
  readonly legal: PokerLegalActions;

  constructor(engine: HoldemEngine, seatIndex: number) {
    const seat = engine.seats[seatIndex]!;
    const legal = engine.legalActions(seatIndex);
    if (!legal) throw new Error('Sitzplatz ist nicht am Zug');
    this.holeCards = seat.holeCards;
    this.community = engine.community;
    this.pot = engine.pot;
    this.currentBet = engine.currentBet;
    this.streetBet = seat.streetBet;
    this.stack = seat.stack;
    this.bigBlind = engine.bigBlind;
    this.activeOpponents = engine.seats.filter((s) => s.isInHand).length - 1;
    this.legal = legal;
  }
}

export interface PokerAIProfile {
  /** Zuschlag auf die benötigte Equity (positiv = tighter). */
  readonly tightness: number;
  /** Wahrscheinlichkeit, mit einer starken Hand zu setzen/erhöhen statt passiv zu spielen. */
  readonly aggression: number;
  /** Bluff-Häufigkeit mit schwachen Händen. */
  readonly bluffRate: number;
  /** Bereitschaft, mit Grenzhänden zu callen. */
  readonly stickiness: number;
}

/** `PokerAIProfile.for(style)` */
export function pokerAIProfileFor(style: PokerStyle): PokerAIProfile {
  switch (style) {
    case 'rock': return { tightness: 0.08, aggression: 0.30, bluffRate: 0.02, stickiness: 0.0 };
    case 'shark': return { tightness: 0.03, aggression: 0.65, bluffRate: 0.08, stickiness: 0.02 };
    case 'maniac': return { tightness: -0.07, aggression: 0.85, bluffRate: 0.22, stickiness: 0.04 };
    case 'station': return { tightness: -0.04, aggression: 0.15, bluffRate: 0.03, stickiness: 0.12 };
  }
}

export const PokerAIProfile = { for: pokerAIProfileFor };

const cardKey = (c: Card): string => `${c.rank}${c.suit}`;

export interface EstimateEquityOptions {
  hole: readonly Card[];
  community: readonly Card[];
  opponents: number;
  /** Standard: 250 */
  iterations?: number;
  random: RandomSource;
}

export const PokerAI = {
  /**
   * Schätzt die Gewinnwahrscheinlichkeit per Monte-Carlo-Simulation gegen
   * zufällige gegnerische Hände (aus den unbekannten Karten).
   */
  estimateEquity(options: EstimateEquityOptions): number {
    const { hole, community, random } = options;
    const iterations = options.iterations ?? 250;
    const opponents = Math.max(1, options.opponents);
    const known = new Set([...hole, ...community].map(cardKey));
    const unknown = Card.standardDeck().filter((c) => !known.has(cardKey(c)));
    let score = 0;

    for (let it = 0; it < iterations; it++) {
      const pool = [...unknown];
      // Partielles Fisher-Yates: nur so viele Karten mischen, wie benötigt werden.
      const needed = opponents * 2 + (5 - community.length);
      for (let i = 0; i < needed; i++) {
        const j = i + random.uniform(pool.length - i);
        const tmp = pool[i]!;
        pool[i] = pool[j]!;
        pool[j] = tmp;
      }
      let cursor = 0;
      const board = [...community];
      while (board.length < 5) { board.push(pool[cursor]!); cursor += 1; }

      const mine = bestHandScore([...hole, ...board]);
      let bestOpponent = -1;
      for (let o = 0; o < opponents; o++) {
        const theirs = bestHandScore([pool[cursor]!, pool[cursor + 1]!, ...board]);
        cursor += 2;
        if (theirs > bestOpponent) bestOpponent = theirs;
      }
      if (bestOpponent >= 0) {
        if (mine > bestOpponent) score += 1;
        else if (mine === bestOpponent) score += 0.5;
      }
    }
    return score / iterations;
  },

  /**
   * Entscheidung eines KI-Gegners. Zufall wird nur für Spielstil-Variation
   * (z. B. Bluffs) verwendet – nie, um Karten zu beeinflussen.
   */
  decide(c: PokerAIContext, style: PokerStyle, random: RandomSource): PokerAction {
    const profile = pokerAIProfileFor(style);
    const equity = PokerAI.estimateEquity({
      hole: c.holeCards, community: c.community, opponents: c.activeOpponents, random,
    });
    const toCall = c.legal.callAmount;
    const fairShare = 1.0 / (c.activeOpponents + 1);
    // Equity relativ zum fairen Anteil (1.0 = durchschnittlich)
    const strength = equity / fairShare - profile.tightness * 4;

    const raise = (potFraction: number): PokerAction => {
      if (!c.legal.canRaise) return toCall > 0 ? PokerAction.call : PokerAction.check;
      const base = Math.max(c.currentBet, 0);
      const size = Math.round((c.pot + toCall) * potFraction);
      let target = Math.max(c.legal.minRaiseTo, base + size);
      // Auf Big-Blind-Vielfache runden – wirkt natürlicher
      target = Math.max(c.legal.minRaiseTo, Math.trunc(target / c.bigBlind) * c.bigBlind);
      if (target >= c.legal.maxRaiseTo || target > c.legal.maxRaiseTo * 0.8) {
        return PokerAction.allIn;
      }
      return PokerAction.raise(target);
    };

    if (toCall === 0) {
      if (strength > 1.5 && random.chance(profile.aggression)) {
        return raise(strength > 2.2 ? 0.9 : 0.6);
      }
      if (strength < 0.9 && random.chance(profile.bluffRate)) {
        return raise(0.5);
      }
      return PokerAction.check;
    }

    const potOdds = toCall / (c.pot + toCall);
    const requiredEquity = potOdds + profile.tightness - profile.stickiness;

    if (equity > requiredEquity + 0.22 && strength > 1.6 && random.chance(profile.aggression)) {
      return raise(strength > 2.4 ? 1.0 : 0.7);
    }
    if (equity >= requiredEquity) {
      return PokerAction.call;
    }
    if (random.chance(profile.bluffRate * 0.4)) {
      return raise(0.6);
    }
    // Sehr kleiner Nachschuss (z. B. Small Blind komplettieren) wird oft gecallt
    if (toCall <= c.bigBlind * 0.5 && equity > fairShare * 0.6) {
      return PokerAction.call;
    }
    return PokerAction.fold;
  },
};
