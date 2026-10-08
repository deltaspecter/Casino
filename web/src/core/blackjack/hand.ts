import { type Card, rankBlackjackValue } from '../cards';

export interface HandValue {
  readonly total: number;
  /** `true`, wenn ein Ass als 11 gezählt wird. */
  readonly isSoft: boolean;
}

function handValueOf(cards: readonly Card[]): HandValue {
  let total = 0;
  let softAces = 0;
  for (const card of cards) {
    total += rankBlackjackValue(card.rank);
    if (card.rank === 14) softAces += 1;
  }
  while (total > 21 && softAces > 0) {
    total -= 10;
    softAces -= 1;
  }
  return { total, isSoft: softAces > 0 };
}

/** Anzeige wie in Swift: Soft-Hände unter 21 als "7/17". */
function handValueDisplay(value: HandValue): string {
  return value.isSoft && value.total < 21 ? `${value.total - 10}/${value.total}` : `${value.total}`;
}

/** `HandValue.of(cards)` und `HandValue.display(value)` wie in Swift. */
export const HandValue = {
  /** Bewertet beliebige Blackjack-Karten: Asse zählen 11, solange die Hand dadurch nicht überkauft. */
  of: handValueOf,
  display: handValueDisplay,
  equals(a: HandValue, b: HandValue): boolean {
    return a.total === b.total && a.isSoft === b.isSoft;
  },
};

export interface BlackjackHandInit {
  id: number;
  cards: readonly Card[];
  bet: number;
  isDoubled?: boolean;
  isStood?: boolean;
  isFromSplit?: boolean;
  isSplitAces?: boolean;
}

/**
 * Eine Blackjack-Hand. Unveränderlich: Die Engine ersetzt Hände durch neue Objekte,
 * statt sie zu verändern – ein einmal gelesenes Objekt bleibt also stabil.
 */
export class BlackjackHand {
  readonly id: number;
  readonly cards: readonly Card[];
  readonly bet: number;
  readonly isDoubled: boolean;
  readonly isStood: boolean;
  /** Entstand durch Split – ein 21 aus zwei Karten zählt dann nicht als Blackjack. */
  readonly isFromSplit: boolean;
  readonly isSplitAces: boolean;

  constructor(init: BlackjackHandInit) {
    this.id = init.id;
    this.cards = Object.freeze([...init.cards]);
    this.bet = init.bet;
    this.isDoubled = init.isDoubled ?? false;
    this.isStood = init.isStood ?? false;
    this.isFromSplit = init.isFromSplit ?? false;
    this.isSplitAces = init.isSplitAces ?? false;
  }

  /** Kopie mit geänderten Feldern (intern von der Engine genutzt). */
  with(patch: Partial<BlackjackHandInit>): BlackjackHand {
    return new BlackjackHand({
      id: this.id, cards: this.cards, bet: this.bet, isDoubled: this.isDoubled, isStood: this.isStood,
      isFromSplit: this.isFromSplit, isSplitAces: this.isSplitAces, ...patch,
    });
  }

  get value(): HandValue { return handValueOf(this.cards); }
  get isBust(): boolean { return this.value.total > 21; }
  get isBlackjack(): boolean { return !this.isFromSplit && this.cards.length === 2 && this.value.total === 21; }

  /** Hand ist fertig gespielt. */
  get isFinished(): boolean {
    return this.isStood || this.isBust || this.isDoubled || this.value.total === 21
      || (this.isSplitAces && this.cards.length >= 2);
  }
}

export type HandOutcome = 'blackjack' | 'win' | 'push' | 'lose' | 'bust';

export function handOutcomeTitle(outcome: HandOutcome): string {
  switch (outcome) {
    case 'blackjack': return 'BLACKJACK';
    case 'win': return 'GEWONNEN';
    case 'push': return 'PUSH';
    case 'lose': return 'VERLOREN';
    case 'bust': return 'BUST';
  }
}

export interface HandResult {
  readonly handID: number;
  readonly outcome: HandOutcome;
  readonly stake: number;
  /** Gesamte Rückzahlung inklusive Einsatz (0 bei Verlust). */
  readonly payout: number;
  /** payout - stake */
  readonly net: number;
}

export function makeHandResult(handID: number, outcome: HandOutcome, stake: number, payout: number): HandResult {
  return Object.freeze({ handID, outcome, stake, payout, net: payout - stake });
}
