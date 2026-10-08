import type { Card } from '../cards';
import type { PokerHandRank } from './handEvaluator';

export type PokerStyle = 'rock' | 'shark' | 'maniac' | 'station';

/** `PokerStyle.allCases` in Swift-Reihenfolge. */
export const ALL_POKER_STYLES: readonly PokerStyle[] = ['rock', 'shark', 'maniac', 'station'];

/**
 * rock: tight-passiv · shark: tight-aggressiv · maniac: loose-aggressiv · station: loose-passiv
 */
export function pokerStyleTitle(style: PokerStyle): string {
  switch (style) {
    case 'rock': return 'Vorsichtig';
    case 'shark': return 'Ausgewogen';
    case 'maniac': return 'Aggressiv';
    case 'station': return 'Calling Station';
  }
}

export type PokerStreet = 'preflop' | 'flop' | 'turn' | 'river' | 'showdown';

/** Reihenfolge der Straßen (entspricht `PokerStreet.rawValue`). */
export const POKER_STREETS: readonly PokerStreet[] = ['preflop', 'flop', 'turn', 'river', 'showdown'];

export function pokerStreetIndex(street: PokerStreet): number {
  return POKER_STREETS.indexOf(street);
}

export function pokerStreetTitle(street: PokerStreet): string {
  switch (street) {
    case 'preflop': return 'Preflop';
    case 'flop': return 'Flop';
    case 'turn': return 'Turn';
    case 'river': return 'River';
    case 'showdown': return 'Showdown';
  }
}

export type PokerAction =
  | { type: 'fold' }
  | { type: 'check' }
  | { type: 'call' }
  /** Setzen bzw. Erhöhen auf den Gesamtbetrag `to` in dieser Setzrunde. */
  | { type: 'raise'; to: number }
  | { type: 'allIn' };

/** Swift-ähnliche Konstruktoren: `PokerAction.fold`, `PokerAction.raise(30)` … */
export const PokerAction = {
  fold: Object.freeze({ type: 'fold' }) as PokerAction,
  check: Object.freeze({ type: 'check' }) as PokerAction,
  call: Object.freeze({ type: 'call' }) as PokerAction,
  allIn: Object.freeze({ type: 'allIn' }) as PokerAction,
  raise: (to: number): PokerAction => ({ type: 'raise', to }),
};

export type PokerActionKind = 'fold' | 'check' | 'call' | 'bet' | 'raise' | 'allIn' | 'smallBlind' | 'bigBlind';

export function pokerActionKindTitle(kind: PokerActionKind): string {
  switch (kind) {
    case 'fold': return 'Fold';
    case 'check': return 'Check';
    case 'call': return 'Call';
    case 'bet': return 'Bet';
    case 'raise': return 'Raise';
    case 'allIn': return 'All-In';
    case 'smallBlind': return 'Small Blind';
    case 'bigBlind': return 'Big Blind';
  }
}

export interface PokerActionRecord {
  readonly kind: PokerActionKind;
  /** Gesamteinsatz des Spielers in dieser Setzrunde nach der Aktion. */
  readonly streetTotal: number;
}

export interface PokerSeatInit {
  id: number;
  name: string;
  isHuman: boolean;
  style: PokerStyle | null;
  stack: number;
}

interface PokerSeatState extends PokerSeatInit {
  holeCards: readonly Card[];
  streetBet: number;
  handContribution: number;
  hasFolded: boolean;
  isAllIn: boolean;
  isSittingOut: boolean;
  hasActed: boolean;
  lastAction: PokerActionRecord | null;
}

/**
 * Ein Sitzplatz am Pokertisch. Unveränderlich: Die Engine ersetzt Sitzplätze bei
 * Änderungen durch neue Objekte (`with`).
 */
export class PokerSeat {
  readonly id: number;
  readonly name: string;
  readonly isHuman: boolean;
  readonly style: PokerStyle | null;
  readonly stack: number;
  readonly holeCards: readonly Card[];
  readonly streetBet: number;
  readonly handContribution: number;
  readonly hasFolded: boolean;
  readonly isAllIn: boolean;
  readonly isSittingOut: boolean;
  readonly hasActed: boolean;
  readonly lastAction: PokerActionRecord | null;

  constructor(init: PokerSeatInit & Partial<PokerSeatState>) {
    this.id = init.id;
    this.name = init.name;
    this.isHuman = init.isHuman;
    this.style = init.style;
    this.stack = init.stack;
    this.holeCards = Object.freeze([...(init.holeCards ?? [])]);
    this.streetBet = init.streetBet ?? 0;
    this.handContribution = init.handContribution ?? 0;
    this.hasFolded = init.hasFolded ?? false;
    this.isAllIn = init.isAllIn ?? false;
    this.isSittingOut = init.isSittingOut ?? false;
    this.hasActed = init.hasActed ?? false;
    this.lastAction = init.lastAction ?? null;
  }

  /** Kopie mit geänderten Feldern. */
  with(patch: Partial<PokerSeatState>): PokerSeat {
    return new PokerSeat({
      id: this.id, name: this.name, isHuman: this.isHuman, style: this.style, stack: this.stack,
      holeCards: this.holeCards, streetBet: this.streetBet, handContribution: this.handContribution,
      hasFolded: this.hasFolded, isAllIn: this.isAllIn, isSittingOut: this.isSittingOut,
      hasActed: this.hasActed, lastAction: this.lastAction, ...patch,
    });
  }

  /** Nimmt an der laufenden Hand teil und hat nicht gefoldet. */
  get isInHand(): boolean { return !this.isSittingOut && !this.hasFolded && this.holeCards.length > 0; }
  /** Kann in dieser Setzrunde noch handeln. */
  get canAct(): boolean { return this.isInHand && !this.isAllIn; }
}

export interface PokerLegalActions {
  readonly canCheck: boolean;
  /** Betrag, der zum Mitgehen nachgelegt werden muss (begrenzt durch den Stack). */
  readonly callAmount: number;
  readonly canRaise: boolean;
  readonly minRaiseTo: number;
  readonly maxRaiseTo: number;
}

export interface ShowdownEntry {
  readonly seatID: number;
  readonly hand: PokerHandRank;
}

export interface PotAward {
  readonly seatID: number;
  readonly amount: number;
  readonly potIndex: number;
  /** Name der Gewinnhand; `null`, wenn der Pot nicht umkämpft war. */
  readonly handName: string | null;
}

export type PokerEvent =
  | { type: 'handStarted'; handNumber: number; buttonSeatID: number }
  | { type: 'blindPosted'; seatID: number; amount: number; isBig: boolean }
  | { type: 'holeCardsDealt'; seatID: number; cards: readonly Card[] }
  | { type: 'action'; seatID: number; record: PokerActionRecord }
  | { type: 'betsCollected'; pot: number }
  | { type: 'communityDealt'; street: PokerStreet; cards: readonly Card[] }
  | { type: 'showdown'; entries: readonly ShowdownEntry[] }
  | { type: 'potAwarded'; award: PotAward }
  | { type: 'handFinished' };

export type PokerErrorKind = 'notEnoughPlayers' | 'handInProgress' | 'notYourTurn' | 'illegalAction';

export class PokerError extends Error {
  readonly kind: PokerErrorKind;
  constructor(kind: PokerErrorKind) {
    super(kind);
    this.name = 'PokerError';
    this.kind = kind;
  }
}
