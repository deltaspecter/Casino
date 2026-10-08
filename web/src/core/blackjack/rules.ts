import type { Card } from '../cards';
import type { HandResult } from './hand';

/**
 * Tischregeln von BlackCasino (im Spiel unter „Rules“ einsehbar):
 * * 1 Standard-Deck (52 Karten), **vor jeder Runde vollständig neu gemischt** –
 *   dadurch ist jede Runde unabhängig von allen vorherigen.
 * * Dealer erhält eine offene und eine verdeckte Karte und prüft bei Ass oder 10er auf Blackjack (Peek).
 * * Dealer zieht bis 16 und **steht auf allen 17** (auch Soft 17, „S17“).
 * * Blackjack zahlt 3:2, normaler Gewinn 1:1, Push gibt den Einsatz zurück.
 * * Double Down auf beliebige erste zwei Karten (auch nach Split), genau eine weitere Karte.
 * * Split bei zwei Karten gleichen Werts, bis zu 4 Hände; geteilte Asse erhalten je eine Karte
 *   und dürfen nicht erneut geteilt werden. 21 nach Split zählt nicht als Blackjack.
 * * Keine Insurance, kein Surrender.
 */
export interface BlackjackRules {
  readonly deckCount: number;
  readonly dealerHitsSoft17: boolean;
  readonly doubleAfterSplit: boolean;
  readonly maxHands: number;
  readonly resplitAces: boolean;
  readonly minBet: number;
  readonly maxBet: number;
}

export const DEFAULT_BLACKJACK_RULES: BlackjackRules = Object.freeze({
  deckCount: 1,
  dealerHitsSoft17: false,
  doubleAfterSplit: true,
  maxHands: 4,
  resplitAces: false,
  minBet: 10,
  maxBet: 5_000,
});

/** `BlackjackRules()` bzw. `BlackjackRules(minBet:maxBet:)` aus Swift. */
export function makeBlackjackRules(overrides: Partial<BlackjackRules> = {}): BlackjackRules {
  return Object.freeze({ ...DEFAULT_BLACKJACK_RULES, ...overrides });
}

export type BlackjackPhase = 'betting' | 'playerTurn' | 'dealerTurn' | 'settled';

export type BlackjackAction = 'hit' | 'stand' | 'double' | 'split';
export const ALL_BLACKJACK_ACTIONS: readonly BlackjackAction[] = ['hit', 'stand', 'double', 'split'];

/** Ereignisse der Einzelspieler-Engine (`BlackjackEngine`). */
export type BlackjackEvent =
  | { type: 'shuffled' }
  | { type: 'dealtToPlayer'; handID: number; card: Card }
  | { type: 'dealtToDealer'; card: Card; faceDown: boolean }
  | { type: 'holeCardRevealed'; card: Card }
  | { type: 'split'; originalHandID: number; newHandID: number; movedCard: Card }
  | { type: 'doubled'; handID: number }
  | { type: 'activeHandChanged'; handID: number | null }
  | { type: 'settled'; results: HandResult[] };

export type BlackjackErrorKind = 'invalidPhase' | 'invalidBet' | 'notYourTurn' | 'illegalAction';

export class BlackjackError extends Error {
  readonly kind: BlackjackErrorKind;
  /** Nur bei `illegalAction` gesetzt. */
  readonly action: BlackjackAction | null;

  constructor(kind: BlackjackErrorKind, action: BlackjackAction | null = null) {
    super(action ? `${kind}(${action})` : kind);
    this.name = 'BlackjackError';
    this.kind = kind;
    this.action = action;
  }

  static readonly invalidPhase = (): BlackjackError => new BlackjackError('invalidPhase');
  static readonly invalidBet = (): BlackjackError => new BlackjackError('invalidBet');
  static readonly notYourTurn = (): BlackjackError => new BlackjackError('notYourTurn');
  static readonly illegalAction = (action: BlackjackAction): BlackjackError => new BlackjackError('illegalAction', action);
}
