import { Card } from '../cards';
import type { RandomSource } from '../random';
import { HandEvaluator, PokerHandRank } from './handEvaluator';
import {
  type PokerAction, type PokerActionKind, type PokerActionRecord, PokerError, type PokerEvent,
  type PokerLegalActions, PokerSeat, type PokerStreet, POKER_STREETS, pokerStreetIndex, type PotAward,
  type ShowdownEntry,
} from './types';

export interface PokerPot {
  readonly amount: number;
  /** Indizes in `seats`, die diesen Pot gewinnen können. */
  readonly eligible: readonly number[];
}

/**
 * No-Limit Texas Hold'em nach Standardregeln, inklusive Side-Pots,
 * Heads-up-Blindregel und automatischem Run-out bei All-in.
 *
 * Zustand, der nach außen gegeben wird (Sitzplätze, Board, Showdown), wird nie nachträglich
 * verändert, sondern bei Änderungen ersetzt.
 */
export class HoldemEngine {
  readonly smallBlind: number;
  readonly bigBlind: number;
  private readonly random: RandomSource;

  private _seats: PokerSeat[];
  private _community: Card[] = [];
  private _street: PokerStreet = 'showdown';
  private _buttonIndex: number;
  private _currentIndex: number | null = null;
  private _currentBet = 0;
  private _lastRaiseSize = 0;
  private _handNumber = 0;
  private _isHandInProgress = false;
  private _lastShowdown: ShowdownEntry[] = [];
  private _lastAwards: PotAward[] = [];
  private deck: Card[] = [];

  /** NUR FÜR TESTS: feste Ziehreihenfolge der nächsten Hand. */
  testOnlyDeckForNextHand: Card[] | null = null;

  constructor(options: { seats: readonly PokerSeat[]; smallBlind: number; bigBlind: number; random: RandomSource }) {
    const { seats, smallBlind, bigBlind, random } = options;
    if (seats.length < 2 || seats.length > 9) throw new RangeError('2 bis 9 Sitzplätze erwartet');
    if (!(smallBlind > 0 && bigBlind >= smallBlind)) throw new RangeError('Ungültige Blinds');
    this._seats = [...seats];
    this.smallBlind = smallBlind;
    this.bigBlind = bigBlind;
    this.random = random;
    // Der erste Button wird zufällig ausgelost.
    this._buttonIndex = random.uniform(seats.length);
  }

  // MARK: - Abfragen

  get seats(): readonly PokerSeat[] { return this._seats; }
  get community(): readonly Card[] { return this._community; }
  get street(): PokerStreet { return this._street; }
  get buttonIndex(): number { return this._buttonIndex; }
  get currentIndex(): number | null { return this._currentIndex; }
  get currentBet(): number { return this._currentBet; }
  get lastRaiseSize(): number { return this._lastRaiseSize; }
  get handNumber(): number { return this._handNumber; }
  get isHandInProgress(): boolean { return this._isHandInProgress; }
  get lastShowdown(): readonly ShowdownEntry[] { return this._lastShowdown; }
  get lastAwards(): readonly PotAward[] { return this._lastAwards; }

  /** NUR FÜR TESTS: Button-Position setzen (Swift: `internal(set) var buttonIndex`). */
  testOnlySetButtonIndex(index: number): void {
    this._buttonIndex = index;
  }

  get pot(): number { return this._seats.reduce((s, seat) => s + seat.handContribution, 0); }
  /** Bereits eingesammelter Pot (ohne Einsätze der aktuellen Setzrunde). */
  get collectedPot(): number { return this._seats.reduce((s, seat) => s + seat.handContribution - seat.streetBet, 0); }
  get currentSeat(): PokerSeat | null { return this._currentIndex === null ? null : this._seats[this._currentIndex]!; }

  legalActions(seatIndex: number): PokerLegalActions | null {
    if (!this._isHandInProgress || seatIndex !== this._currentIndex) return null;
    const seat = this._seats[seatIndex]!;
    const toCall = Math.max(0, this._currentBet - seat.streetBet);
    const maxTo = seat.streetBet + seat.stack;
    const minTo = this._currentBet === 0
      ? Math.min(this.bigBlind, maxTo)
      : Math.min(this._currentBet + Math.max(this._lastRaiseSize, this.bigBlind), maxTo);
    const opponentsCanRespond = this._seats.some((s, i) => i !== seatIndex && s.canAct);
    return {
      canCheck: toCall === 0,
      callAmount: Math.min(toCall, seat.stack),
      canRaise: maxTo > this._currentBet && opponentsCanRespond,
      minRaiseTo: minTo,
      maxRaiseTo: maxTo,
    };
  }

  // MARK: - Tischverwaltung (nur zwischen den Händen)

  replaceSeat(index: number, seat: PokerSeat): void {
    if (this._isHandInProgress) throw new PokerError('handInProgress');
    this.setSeat(index, seat);
  }

  setStack(amount: number, seatIndex: number): void {
    if (this._isHandInProgress) throw new PokerError('handInProgress');
    this.setSeat(seatIndex, this._seats[seatIndex]!.with({ stack: Math.max(0, amount) }));
  }

  // MARK: - Ablauf

  startHand(): PokerEvent[] {
    if (this._isHandInProgress) throw new PokerError('handInProgress');
    if (this._seats.filter((s) => s.stack > 0).length < 2) throw new PokerError('notEnoughPlayers');

    this._handNumber += 1;
    this._isHandInProgress = true;
    this._community = [];
    this._lastShowdown = [];
    this._lastAwards = [];
    this._seats = this._seats.map((s) => s.with({
      holeCards: [], streetBet: 0, handContribution: 0, hasFolded: false, isAllIn: false,
      hasActed: false, lastAction: null, isSittingOut: s.stack === 0,
    }));

    const notSittingOut = (s: PokerSeat): boolean => !s.isSittingOut;
    this._buttonIndex = this.nextIndex(this._buttonIndex, notSittingOut);
    // RNG → frisch gemischtes 52-Karten-Deck → Ausgabe. Die KI hat hierauf keinen Zugriff.
    if (this.testOnlyDeckForNextHand) {
      this.deck = [...this.testOnlyDeckForNextHand].reverse();
      this.testOnlyDeckForNextHand = null;
    } else {
      const deck = Card.standardDeck();
      this.random.shuffle(deck);
      this.deck = deck;
    }

    const events: PokerEvent[] = [
      { type: 'handStarted', handNumber: this._handNumber, buttonSeatID: this._seats[this._buttonIndex]!.id },
    ];

    const activeCount = this._seats.filter(notSittingOut).length;
    let sbIndex: number;
    let bbIndex: number;
    if (activeCount === 2) {
      // Heads-up: Button zahlt den Small Blind und handelt preflop zuerst.
      sbIndex = this._buttonIndex;
      bbIndex = this.nextIndex(this._buttonIndex, notSittingOut);
    } else {
      sbIndex = this.nextIndex(this._buttonIndex, notSittingOut);
      bbIndex = this.nextIndex(sbIndex, notSittingOut);
    }
    events.push(this.postBlind(sbIndex, this.smallBlind, false));
    events.push(this.postBlind(bbIndex, this.bigBlind, true));
    // Ein zu kurzer Big Blind (All-in) senkt den zu deckenden Betrag.
    this._currentBet = Math.max(...this._seats.map((s) => s.streetBet));
    this._lastRaiseSize = this.bigBlind;
    this._street = 'preflop';

    // Zwei Runden à eine Karte, beginnend links vom Button
    const order: number[] = [];
    let idx = this._buttonIndex;
    for (let k = 0; k < activeCount; k++) {
      idx = this.nextIndex(idx, notSittingOut);
      order.push(idx);
    }
    for (let round = 0; round < 2; round++) {
      for (const i of order) {
        const card = this.drawCard();
        this.setSeat(i, this._seats[i]!.with({ holeCards: [...this._seats[i]!.holeCards, card] }));
      }
    }
    for (const i of order) {
      events.push({ type: 'holeCardsDealt', seatID: this._seats[i]!.id, cards: this._seats[i]!.holeCards });
    }

    this._currentIndex = null;
    const first = this.firstToAct(bbIndex);
    if (first !== null) {
      this._currentIndex = first;
      if (this.isBettingRoundComplete) events.push(...this.advanceStreet());
    } else {
      events.push(...this.advanceStreet());
    }
    return events;
  }

  apply(action: PokerAction, seatIndex: number): PokerEvent[] {
    const legal = this.legalActions(seatIndex);
    if (!this._isHandInProgress || seatIndex !== this._currentIndex || !legal) {
      throw new PokerError('notYourTurn');
    }
    const events: PokerEvent[] = [];
    const seat = this._seats[seatIndex]!;

    switch (action.type) {
      case 'fold':
        this.setSeat(seatIndex, seat.with({ hasFolded: true, lastAction: { kind: 'fold', streetTotal: seat.streetBet } }));
        break;
      case 'check':
        if (!legal.canCheck) throw new PokerError('illegalAction');
        this.setSeat(seatIndex, seat.with({ lastAction: { kind: 'check', streetTotal: seat.streetBet } }));
        break;
      case 'call': {
        if (legal.callAmount <= 0) throw new PokerError('illegalAction');
        this.commit(legal.callAmount, seatIndex);
        const s = this._seats[seatIndex]!;
        const kind: PokerActionKind = s.isAllIn ? 'allIn' : 'call';
        this.setSeat(seatIndex, s.with({ lastAction: { kind, streetTotal: s.streetBet } }));
        break;
      }
      case 'raise': {
        const to = action.to;
        if (!legal.canRaise || !Number.isInteger(to) || to > legal.maxRaiseTo
          || !(to >= legal.minRaiseTo || to === legal.maxRaiseTo)) {
          throw new PokerError('illegalAction');
        }
        this.applyRaise(to, seatIndex);
        break;
      }
      case 'allIn':
        if (legal.maxRaiseTo > this._currentBet && legal.canRaise) {
          this.applyRaise(legal.maxRaiseTo, seatIndex);
        } else if (legal.callAmount > 0) {
          this.commit(legal.callAmount, seatIndex);
          const s = this._seats[seatIndex]!;
          this.setSeat(seatIndex, s.with({ lastAction: { kind: 'allIn', streetTotal: s.streetBet } }));
        } else {
          throw new PokerError('illegalAction');
        }
        break;
    }
    this.setSeat(seatIndex, this._seats[seatIndex]!.with({ hasActed: true }));
    events.push({ type: 'action', seatID: this._seats[seatIndex]!.id, record: this._seats[seatIndex]!.lastAction! });

    const remaining = this._seats.map((s, i) => (s.isInHand ? i : -1)).filter((i) => i >= 0);
    if (remaining.length === 1) {
      events.push(...this.awardUncontested(remaining[0]!));
      return events;
    }

    if (this.isBettingRoundComplete) {
      events.push(...this.advanceStreet());
    } else {
      this._currentIndex = this.nextIndex(seatIndex, (s) => s.canAct);
    }
    return events;
  }

  // MARK: - Interna

  private setSeat(index: number, seat: PokerSeat): void {
    const next = [...this._seats];
    next[index] = seat;
    this._seats = next;
  }

  private drawCard(): Card {
    const card = this.deck.pop();
    if (!card) throw new Error('Deck leer');
    return card;
  }

  private applyRaise(to: number, seatIndex: number): void {
    const previousBet = this._currentBet;
    const wasBet = previousBet === 0;
    this.commit(to - this._seats[seatIndex]!.streetBet, seatIndex);
    const raiseSize = to - previousBet;
    if (raiseSize >= this._lastRaiseSize) this._lastRaiseSize = raiseSize;
    this._currentBet = Math.max(this._currentBet, to);
    // Erneute Handlungsmöglichkeit für alle anderen
    this._seats = this._seats.map((s, i) => (i !== seatIndex && s.canAct ? s.with({ hasActed: false }) : s));
    const s = this._seats[seatIndex]!;
    const kind: PokerActionKind = s.isAllIn ? 'allIn' : (wasBet ? 'bet' : 'raise');
    const record: PokerActionRecord = { kind, streetTotal: s.streetBet };
    this.setSeat(seatIndex, s.with({ lastAction: record }));
  }

  private commit(amount: number, seatIndex: number): void {
    const s = this._seats[seatIndex]!;
    const a = Math.min(amount, s.stack);
    const stack = s.stack - a;
    this.setSeat(seatIndex, s.with({
      stack,
      streetBet: s.streetBet + a,
      handContribution: s.handContribution + a,
      isAllIn: stack === 0 ? true : s.isAllIn,
    }));
  }

  private postBlind(seatIndex: number, amount: number, isBig: boolean): PokerEvent {
    this.commit(amount, seatIndex);
    const s = this._seats[seatIndex]!;
    this.setSeat(seatIndex, s.with({ lastAction: { kind: isBig ? 'bigBlind' : 'smallBlind', streetTotal: s.streetBet } }));
    return { type: 'blindPosted', seatID: s.id, amount: s.streetBet, isBig };
  }

  private get isBettingRoundComplete(): boolean {
    const actors = this._seats.filter((s) => s.canAct);
    if (actors.length === 0) return true;
    if (actors.length === 1) {
      // Alle anderen sind all-in: Wer den Einsatz bereits gedeckt hat, muss nicht mehr handeln.
      return actors[0]!.streetBet >= this._currentBet;
    }
    return actors.every((s) => s.hasActed && s.streetBet === this._currentBet);
  }

  private firstToAct(after: number): number | null {
    if (!this._seats.some((s) => s.canAct)) return null;
    return this.nextIndex(after, (s) => s.canAct);
  }

  private nextIndex(after: number, predicate: (seat: PokerSeat) => boolean): number {
    let i = after;
    for (let k = 0; k < this._seats.length; k++) {
      i = (i + 1) % this._seats.length;
      if (predicate(this._seats[i]!)) return i;
    }
    return after;
  }

  private advanceStreet(): PokerEvent[] {
    const events: PokerEvent[] = [];
    for (;;) {
      this._seats = this._seats.map((s) => s.with({ streetBet: 0, hasActed: false }));
      this._currentBet = 0;
      this._lastRaiseSize = this.bigBlind;
      events.push({ type: 'betsCollected', pot: this.pot });

      if (pokerStreetIndex(this._street) >= pokerStreetIndex('river')) {
        events.push(...this.showdown());
        return events;
      }

      this._street = POKER_STREETS[pokerStreetIndex(this._street) + 1]!;
      this.drawCard(); // Burn-Karte
      const count = this._street === 'flop' ? 3 : 1;
      const newCards: Card[] = [];
      for (let k = 0; k < count; k++) newCards.push(this.drawCard());
      this._community = [...this._community, ...newCards];
      events.push({ type: 'communityDealt', street: this._street, cards: newCards });

      // Weiter setzen nur, wenn mindestens zwei Spieler noch handeln können
      if (this._seats.filter((s) => s.canAct).length >= 2) {
        this._currentIndex = this.nextIndex(this._buttonIndex, (s) => s.canAct);
        return events;
      }
      this._currentIndex = null;
    }
  }

  private awardUncontested(seatIndex: number): PokerEvent[] {
    const amount = this.pot;
    const s = this._seats[seatIndex]!;
    this.setSeat(seatIndex, s.with({ stack: s.stack + amount }));
    const award: PotAward = { seatID: s.id, amount, potIndex: 0, handName: null };
    this._lastAwards = [award];
    this.finishHand();
    return [{ type: 'betsCollected', pot: amount }, { type: 'potAwarded', award }, { type: 'handFinished' }];
  }

  /** Teilt den Gesamtpot in Haupt- und Side-Pots auf. */
  buildPots(): PokerPot[] {
    const remaining = this._seats.map((s) => s.handContribution);
    const pots: { amount: number; eligible: number[] }[] = [];
    for (;;) {
      const eligible = this._seats.map((s, i) => (s.isInHand && remaining[i]! > 0 ? i : -1)).filter((i) => i >= 0);
      if (eligible.length === 0) break;
      const level = Math.min(...eligible.map((i) => remaining[i]!));
      let amount = 0;
      for (let i = 0; i < this._seats.length; i++) {
        const take = Math.min(remaining[i]!, level);
        amount += take;
        remaining[i] = remaining[i]! - take;
      }
      pots.push({ amount, eligible });
    }
    // Übrige Beiträge gefoldeter Spieler fallen in den letzten Pot.
    const leftover = remaining.reduce((a, b) => a + b, 0);
    if (leftover > 0 && pots.length > 0) pots[pots.length - 1]!.amount += leftover;
    return pots;
  }

  private showdown(): PokerEvent[] {
    this._street = 'showdown';
    this._currentIndex = null;
    const contenders = this._seats.map((s, i) => (s.isInHand ? i : -1)).filter((i) => i >= 0);
    const ranks = new Map<number, PokerHandRank>();
    for (const i of contenders) ranks.set(i, HandEvaluator.bestHand([...this._seats[i]!.holeCards, ...this._community]));
    this._lastShowdown = contenders.map((i) => ({ seatID: this._seats[i]!.id, hand: ranks.get(i)! }));

    const events: PokerEvent[] = [{ type: 'showdown', entries: this._lastShowdown }];
    const awards: PotAward[] = [];
    this.buildPots().forEach((pot, potIndex) => {
      let best: PokerHandRank | null = null;
      for (const i of pot.eligible) {
        const r = ranks.get(i);
        if (r && (best === null || PokerHandRank.compare(r, best) > 0)) best = r;
      }
      if (!best) return;
      const bestRank = best;
      // Gewinner in Sitzreihenfolge ab links vom Button (für ungerade Restchips)
      const winners = this.orderFromButton(pot.eligible.filter((i) => ranks.get(i)!.equals(bestRank)));
      const share = Math.floor(pot.amount / winners.length);
      let oddChips = pot.amount % winners.length;
      for (const w of winners) {
        let amount = share;
        if (oddChips > 0) { amount += 1; oddChips -= 1; }
        const s = this._seats[w]!;
        this.setSeat(w, s.with({ stack: s.stack + amount }));
        const handName = pot.eligible.length > 1 ? bestRank.name : null;
        awards.push({ seatID: s.id, amount, potIndex, handName });
      }
    });
    this._lastAwards = awards;
    for (const award of awards) events.push({ type: 'potAwarded', award });
    this.finishHand();
    events.push({ type: 'handFinished' });
    return events;
  }

  private orderFromButton(indices: number[]): number[] {
    const n = this._seats.length;
    const key = (i: number): number => (i - this._buttonIndex - 1 + n) % n;
    return [...indices].sort((l, r) => key(l) - key(r));
  }

  private finishHand(): void {
    this._isHandInProgress = false;
    this._currentIndex = null;
    this._seats = this._seats.map((s) => (s.streetBet === 0 ? s : s.with({ streetBet: 0 })));
  }
}
