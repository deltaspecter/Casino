import type { AchievementDefinition, MissionDefinition } from './definitions';

export type WalletErrorKind = 'insufficientChips' | 'invalidAmount';

export class WalletError extends Error {
  readonly kind: WalletErrorKind;
  /** Nur bei `insufficientChips` gesetzt. */
  readonly needed: number | null;
  readonly available: number | null;

  constructor(kind: WalletErrorKind, needed: number | null = null, available: number | null = null) {
    super(kind === 'insufficientChips' ? `insufficientChips(needed: ${needed}, available: ${available})` : kind);
    this.name = 'WalletError';
    this.kind = kind;
    this.needed = needed;
    this.available = available;
  }

  static insufficientChips(needed: number, available: number): WalletError {
    return new WalletError('insufficientChips', needed, available);
  }

  static invalidAmount(): WalletError {
    return new WalletError('invalidAmount');
  }
}

export type ClaimErrorKind = 'notAvailable' | 'alreadyClaimed';

export class ClaimError extends Error {
  readonly kind: ClaimErrorKind;
  constructor(kind: ClaimErrorKind) {
    super(kind);
    this.name = 'ClaimError';
    this.kind = kind;
  }
}

/** Ergebnis einer Spielrunde aus Sicht des Fortschrittssystems. */
export type GameEvent =
  | { type: 'blackjackRound'; stake: number; payout: number; handsWon: number; pushes: number; blackjacks: number; hands: number }
  | { type: 'pokerHand'; contributed: number; won: number }
  | { type: 'slotSpin'; bet: number; payout: number };

/** Swift-ähnliche Konstruktoren: `GameEvent.slotSpin({ bet, payout })` … */
export const GameEvent = {
  blackjackRound: (e: Omit<Extract<GameEvent, { type: 'blackjackRound' }>, 'type'>): GameEvent => ({ type: 'blackjackRound', ...e }),
  pokerHand: (e: Omit<Extract<GameEvent, { type: 'pokerHand' }>, 'type'>): GameEvent => ({ type: 'pokerHand', ...e }),
  slotSpin: (e: Omit<Extract<GameEvent, { type: 'slotSpin' }>, 'type'>): GameEvent => ({ type: 'slotSpin', ...e }),
};

export type ProgressNotification =
  | { type: 'missionCompleted'; mission: MissionDefinition }
  | { type: 'achievementUnlocked'; achievement: AchievementDefinition };

export interface LoginBonusOffer {
  readonly streakDay: number;
  readonly amount: number;
}
