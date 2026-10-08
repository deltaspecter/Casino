import { type Card, rankBlackjackValue } from '../cards';
import type { BlackjackHand } from './hand';
import type { BlackjackAction } from './rules';

const inRange = (v: number, lo: number, hi: number): boolean => v >= lo && v <= hi;

/**
 * Strategie für Blackjack-Bot-Spieler an Online-Tischen.
 *
 * Der Bot entscheidet ausschließlich anhand von Informationen, die jeder Spieler am Tisch sieht:
 * seine eigene Hand und die offene Dealer-Karte. Er kennt weder die verdeckte Dealer-Karte
 * noch die Reihenfolge des Decks und hat keinen Zugriff auf den Zufallsgenerator.
 * Gespielt wird eine vereinfachte Grundstrategie (Basic Strategy, S17).
 */
export const BlackjackBot = {
  decide(hand: BlackjackHand, dealerUpcard: Card, available: ReadonlySet<BlackjackAction>): BlackjackAction {
    const up = rankBlackjackValue(dealerUpcard.rank);
    const value = hand.value;

    // Paare
    if (available.has('split') && hand.cards.length === 2) {
      const pair = rankBlackjackValue(hand.cards[0]!.rank);
      if (pair === 11 || pair === 8) return 'split';
      if (pair === 9 && ![7, 10, 11].includes(up)) return 'split';
      if ((pair === 7 && up <= 7)
        || (pair === 6 && inRange(up, 2, 6))
        || (pair === 3 && inRange(up, 4, 7))
        || (pair === 2 && inRange(up, 4, 7))) {
        return 'split';
      }
    }

    // Soft-Hände
    if (value.isSoft) {
      const t = value.total;
      if (t >= 19) return 'stand';
      if (t === 18) {
        if (available.has('double') && inRange(up, 3, 6)) return 'double';
        return up >= 9 ? 'hit' : 'stand';
      }
      if (t === 17) {
        if (available.has('double') && inRange(up, 3, 6)) return 'double';
        return 'hit';
      }
      if (t === 15 || t === 16) {
        if (available.has('double') && inRange(up, 4, 6)) return 'double';
        return 'hit';
      }
      if (available.has('double') && inRange(up, 5, 6)) return 'double';
      return 'hit';
    }

    // Harte Hände
    const t = value.total;
    if (t >= 17) return 'stand';
    if (inRange(t, 13, 16)) return up <= 6 ? 'stand' : 'hit';
    if (t === 12) return inRange(up, 4, 6) ? 'stand' : 'hit';
    if (t === 11) return available.has('double') ? 'double' : 'hit';
    if (t === 10) return available.has('double') && up <= 9 ? 'double' : 'hit';
    if (t === 9) return available.has('double') && inRange(up, 3, 6) ? 'double' : 'hit';
    return 'hit';
  },
};
