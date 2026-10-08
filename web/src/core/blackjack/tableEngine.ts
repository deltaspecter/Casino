import { type Card, Shoe, rankBlackjackValue } from '../cards';
import type { RandomSource } from '../random';
import { BlackjackHand, HandValue, type HandOutcome, type HandResult, makeHandResult } from './hand';
import {
  type BlackjackAction, BlackjackError, type BlackjackPhase, type BlackjackRules, DEFAULT_BLACKJACK_RULES,
} from './rules';

/** Ergebnis aller Hände eines Sitzplatzes. */
export interface SeatResult {
  readonly seatID: number;
  readonly results: readonly HandResult[];
  /** Summe der Einsätze */
  readonly stake: number;
  /** Summe der Rückzahlungen */
  readonly payout: number;
}

function makeSeatResult(seatID: number, results: readonly HandResult[]): SeatResult {
  return Object.freeze({
    seatID,
    results,
    stake: results.reduce((s, r) => s + r.stake, 0),
    payout: results.reduce((s, r) => s + r.payout, 0),
  });
}

/** Ein Sitzplatz (unveränderlich; die Engine ersetzt ihn bei Änderungen). */
export class BlackjackSeat {
  readonly seatID: number;
  readonly hands: readonly BlackjackHand[];
  readonly results: readonly HandResult[];

  constructor(seatID: number, hands: readonly BlackjackHand[], results: readonly HandResult[] = []) {
    this.seatID = seatID;
    this.hands = Object.freeze([...hands]);
    this.results = Object.freeze([...results]);
  }

  get totalStake(): number { return this.hands.reduce((s, h) => s + h.bet, 0); }
}

export type BlackjackTableEvent =
  | { type: 'shuffled' }
  | { type: 'dealtToPlayer'; seatID: number; handID: number; card: Card }
  | { type: 'dealtToDealer'; card: Card; faceDown: boolean }
  | { type: 'holeCardRevealed'; card: Card }
  | { type: 'split'; seatID: number; originalHandID: number; newHandID: number; movedCard: Card }
  | { type: 'doubled'; seatID: number; handID: number }
  | { type: 'turnChanged'; seatID: number | null; handID: number | null }
  | { type: 'settled'; seatResults: SeatResult[] };

export interface BlackjackTurn {
  /** Index in `seats` */
  readonly seat: number;
  /** Index der Hand im Sitzplatz */
  readonly hand: number;
}

export interface BlackjackBet {
  seatID: number;
  bet: number;
}

/**
 * Blackjack-Tisch mit einem oder mehreren Sitzplätzen gegen **einen** Dealer.
 *
 * Dies ist die einzige Blackjack-Regelimplementierung. Offline nutzt `BlackjackEngine`
 * sie mit einem Platz. Regeln: siehe `BlackjackRules`.
 *
 * * Jeder Platz hat eigene Hände; Aktionen eines Platzes betreffen nur dessen Hände.
 * * Kartenreihenfolge: Runde 1 an alle Plätze (in Sitzreihenfolge), Dealer offen,
 *   Runde 2 an alle Plätze, Dealer verdeckt. Danach zieht jede Aktion die oberste Karte.
 * * Die Plätze sind nacheinander am Zug; innerhalb eines Platzes die Hände von links nach rechts.
 */
export class BlackjackTableEngine {
  readonly rules: BlackjackRules;
  private readonly random: RandomSource;

  private readonly _shoe: Shoe;
  private _phase: BlackjackPhase = 'betting';
  private _seats: BlackjackSeat[] = [];
  private _dealerCards: Card[] = [];
  private _isHoleCardRevealed = false;
  private _turn: BlackjackTurn | null = null;
  private nextHandID = 0;

  /** NUR FÜR TESTS: feste Ziehreihenfolge der nächsten Runde. */
  testOnlyDeckForNextRound: Card[] | null = null;

  constructor(options: { rules?: BlackjackRules; random: RandomSource }) {
    this.rules = options.rules ?? DEFAULT_BLACKJACK_RULES;
    this.random = options.random;
    this._shoe = new Shoe(this.rules.deckCount, this.random);
  }

  // MARK: - Abfragen

  get shoe(): Shoe { return this._shoe; }
  get phase(): BlackjackPhase { return this._phase; }
  get seats(): readonly BlackjackSeat[] { return this._seats; }
  get dealerCards(): readonly Card[] { return this._dealerCards; }
  get isHoleCardRevealed(): boolean { return this._isHoleCardRevealed; }
  /** Aktueller Zug: Index in `seats` und Index der Hand. */
  get turn(): BlackjackTurn | null { return this._turn; }

  get currentSeatID(): number | null {
    return this._turn ? this._seats[this._turn.seat]!.seatID : null;
  }

  get currentHand(): BlackjackHand | null {
    return this._turn ? this._seats[this._turn.seat]!.hands[this._turn.hand]! : null;
  }

  seat(seatID: number): BlackjackSeat | null {
    return this._seats.find((s) => s.seatID === seatID) ?? null;
  }

  /** Für Spieler sichtbarer Dealer-Wert (nur offene Karten). */
  get dealerVisibleValue(): HandValue {
    return HandValue.of(this._isHoleCardRevealed ? this._dealerCards : this._dealerCards.slice(0, 1));
  }

  /** Erlaubte Aktionen – ausschließlich für den Platz, der gerade am Zug ist. */
  availableActions(seatID: number): Set<BlackjackAction> {
    const turn = this._turn;
    if (this._phase !== 'playerTurn' || !turn || this._seats[turn.seat]!.seatID !== seatID) return new Set();
    const seat = this._seats[turn.seat]!;
    const hand = seat.hands[turn.hand]!;
    if (hand.isFinished) return new Set();
    const actions = new Set<BlackjackAction>(['hit', 'stand']);
    if (hand.cards.length === 2 && !hand.isSplitAces && (!hand.isFromSplit || this.rules.doubleAfterSplit)) {
      actions.add('double');
    }
    if (hand.cards.length === 2
      && rankBlackjackValue(hand.cards[0]!.rank) === rankBlackjackValue(hand.cards[1]!.rank)
      && seat.hands.length < this.rules.maxHands
      && (!hand.isSplitAces || this.rules.resplitAces)) {
      actions.add('split');
    }
    return actions;
  }

  /** Zusätzlicher Einsatz für Double oder Split. */
  additionalStake(action: BlackjackAction, seatID: number): number {
    const hand = this.currentHand;
    if (this.currentSeatID !== seatID || !hand) return 0;
    switch (action) {
      case 'double':
      case 'split':
        return hand.bet;
      case 'hit':
      case 'stand':
        return 0;
    }
  }

  // MARK: - Ablauf

  /** Startet eine Runde. `bets` in Sitzreihenfolge; jeder Platz höchstens einmal. */
  startRound(bets: readonly BlackjackBet[]): BlackjackTableEvent[] {
    if (this._phase !== 'betting' && this._phase !== 'settled') throw BlackjackError.invalidPhase();
    if (bets.length === 0 || new Set(bets.map((b) => b.seatID)).size !== bets.length) throw BlackjackError.invalidBet();
    if (!bets.every((b) => Number.isInteger(b.bet) && b.bet >= this.rules.minBet && b.bet <= this.rules.maxBet)) {
      throw BlackjackError.invalidBet();
    }

    const events: BlackjackTableEvent[] = [];
    this._dealerCards = [];
    this._isHoleCardRevealed = false;
    this._turn = null;
    this.nextHandID = 0;

    // RNG → Mischen → Ausgabe → Regeln → Ergebnis. Jede Runde mit frisch gemischtem Deck.
    if (this.testOnlyDeckForNextRound) {
      this._shoe.testOnlySetDrawOrder(this.testOnlyDeckForNextRound);
      this.testOnlyDeckForNextRound = null;
    } else {
      this._shoe.reshuffle(this.random);
    }
    events.push({ type: 'shuffled' });

    this._seats = bets.map((b) => new BlackjackSeat(b.seatID, [new BlackjackHand({ id: this.makeHandID(), cards: [], bet: b.bet })]));

    for (let i = 0; i < this._seats.length; i++) events.push(this.deal(i, 0));
    events.push(this.dealToDealer(false));
    for (let i = 0; i < this._seats.length; i++) events.push(this.deal(i, 0));
    events.push(this.dealToDealer(true));

    const dealerHasBlackjack = HandValue.of(this._dealerCards).total === 21;
    if (dealerHasBlackjack || !this.hasLiveHands) {
      // Peek: Dealer-Blackjack beendet die Runde sofort. Haben alle Spieler Blackjack,
      // gibt es nichts mehr zu entscheiden.
      events.push(this.revealHoleCard());
      events.push(this.settle());
      return events;
    }

    this._phase = 'playerTurn';
    this._turn = this.nextTurn(null);
    events.push(this.turnEvent());
    return events;
  }

  perform(action: BlackjackAction, seatID: number): BlackjackTableEvent[] {
    const turn = this._turn;
    if (this._phase !== 'playerTurn' || !turn) throw BlackjackError.invalidPhase();
    if (this._seats[turn.seat]!.seatID !== seatID) throw BlackjackError.notYourTurn();
    if (!this.availableActions(seatID).has(action)) throw BlackjackError.illegalAction(action);

    const events: BlackjackTableEvent[] = [];
    const s = turn.seat;
    const h = turn.hand;
    switch (action) {
      case 'hit':
        events.push(this.deal(s, h));
        break;
      case 'stand':
        this.updateHand(s, h, (hand) => hand.with({ isStood: true }));
        break;
      case 'double': {
        const hand = this.updateHand(s, h, (old) => old.with({ bet: old.bet * 2, isDoubled: true }));
        events.push({ type: 'doubled', seatID, handID: hand.id });
        events.push(this.deal(s, h));
        break;
      }
      case 'split':
        events.push(...this.split(s, h));
        break;
    }

    if (this._seats[s]!.hands[h]!.isFinished) {
      events.push(...this.advance());
    }
    return events;
  }

  /** Wenn ein Platz den Tisch verlässt oder die Bedenkzeit abläuft: alle seine offenen Hände stehen lassen. */
  standAll(seatID: number): BlackjackTableEvent[] {
    const events: BlackjackTableEvent[] = [];
    while (this._phase === 'playerTurn' && this.currentSeatID === seatID) {
      try {
        events.push(...this.perform('stand', seatID));
      } catch {
        break;
      }
    }
    return events;
  }

  // MARK: - Interna

  private makeHandID(): number {
    return this.nextHandID++;
  }

  private updateHand(s: number, h: number, change: (hand: BlackjackHand) => BlackjackHand): BlackjackHand {
    const seat = this._seats[s]!;
    const hands = [...seat.hands];
    const updated = change(hands[h]!);
    hands[h] = updated;
    this._seats[s] = new BlackjackSeat(seat.seatID, hands, seat.results);
    return updated;
  }

  /** Eine Hand ist „lebendig“, wenn der Dealer gegen sie noch ziehen muss. */
  private get hasLiveHands(): boolean {
    return this._seats.some((seat) => seat.hands.some((h) => !h.isBust && !h.isBlackjack));
  }

  private deal(s: number, h: number): BlackjackTableEvent {
    const card = this._shoe.draw(this.random);
    const hand = this.updateHand(s, h, (old) => old.with({ cards: [...old.cards, card] }));
    return { type: 'dealtToPlayer', seatID: this._seats[s]!.seatID, handID: hand.id, card };
  }

  private dealToDealer(faceDown: boolean): BlackjackTableEvent {
    const card = this._shoe.draw(this.random);
    this._dealerCards = [...this._dealerCards, card];
    return { type: 'dealtToDealer', card, faceDown };
  }

  private revealHoleCard(): BlackjackTableEvent {
    this._isHoleCardRevealed = true;
    return { type: 'holeCardRevealed', card: this._dealerCards[1]! };
  }

  private split(s: number, h: number): BlackjackTableEvent[] {
    const seat = this._seats[s]!;
    const original = seat.hands[h]!;
    const moved = original.cards[1]!;
    const aces = original.cards[0]!.rank === 14;
    const first = new BlackjackHand({
      id: original.id, cards: [original.cards[0]!], bet: original.bet, isFromSplit: true, isSplitAces: aces,
    });
    const second = new BlackjackHand({
      id: this.makeHandID(), cards: [moved], bet: original.bet, isFromSplit: true, isSplitAces: aces,
    });
    const hands = [...seat.hands];
    hands[h] = first;
    hands.splice(h + 1, 0, second);
    this._seats[s] = new BlackjackSeat(seat.seatID, hands, seat.results);
    return [
      { type: 'split', seatID: seat.seatID, originalHandID: first.id, newHandID: second.id, movedCard: moved },
      this.deal(s, h),
      this.deal(s, h + 1),
    ];
  }

  private turnEvent(): BlackjackTableEvent {
    const turn = this._turn;
    if (!turn) return { type: 'turnChanged', seatID: null, handID: null };
    const seat = this._seats[turn.seat]!;
    return { type: 'turnChanged', seatID: seat.seatID, handID: seat.hands[turn.hand]!.id };
  }

  /** Nächste offene Hand: zuerst weitere Hände desselben Platzes, dann die folgenden Plätze. */
  private nextTurn(current: BlackjackTurn | null): BlackjackTurn | null {
    let s = current?.seat ?? 0;
    let h = current ? current.hand + 1 : 0;
    while (s < this._seats.length) {
      const hands = this._seats[s]!.hands;
      while (h < hands.length) {
        if (!hands[h]!.isFinished) return { seat: s, hand: h };
        h += 1;
      }
      s += 1;
      h = 0;
    }
    return null;
  }

  private advance(): BlackjackTableEvent[] {
    this._turn = this.nextTurn(this._turn);
    if (this._turn) return [this.turnEvent()];
    return [{ type: 'turnChanged', seatID: null, handID: null }, ...this.playDealer()];
  }

  private playDealer(): BlackjackTableEvent[] {
    this._phase = 'dealerTurn';
    const events: BlackjackTableEvent[] = [this.revealHoleCard()];
    // Der Dealer zieht nur, wenn noch Hände offen sind, die nicht überkauft und kein Blackjack sind.
    if (this.hasLiveHands) {
      while (this.shouldDealerHit) events.push(this.dealToDealer(false));
    }
    events.push(this.settle());
    return events;
  }

  private get shouldDealerHit(): boolean {
    const value = HandValue.of(this._dealerCards);
    if (value.total < 17) return true;
    return value.total === 17 && value.isSoft && this.rules.dealerHitsSoft17;
  }

  private settle(): BlackjackTableEvent {
    const dealer = HandValue.of(this._dealerCards);
    const dealerBlackjack = this._dealerCards.length === 2 && dealer.total === 21;

    this._seats = this._seats.map((seat) => {
      const results = seat.hands.map((hand) => {
        let outcome: HandOutcome;
        let payout: number;
        if (hand.isBust) {
          outcome = 'bust'; payout = 0;
        } else if (hand.isBlackjack && !dealerBlackjack) {
          outcome = 'blackjack'; payout = hand.bet + Math.floor((hand.bet * 3) / 2);
        } else if (dealerBlackjack) {
          outcome = hand.isBlackjack ? 'push' : 'lose';
          payout = hand.isBlackjack ? hand.bet : 0;
        } else if (dealer.total > 21 || hand.value.total > dealer.total) {
          outcome = 'win'; payout = hand.bet * 2;
        } else if (hand.value.total === dealer.total) {
          outcome = 'push'; payout = hand.bet;
        } else {
          outcome = 'lose'; payout = 0;
        }
        return makeHandResult(hand.id, outcome, hand.bet, payout);
      });
      return new BlackjackSeat(seat.seatID, seat.hands, results);
    });
    this._phase = 'settled';
    this._turn = null;
    return { type: 'settled', seatResults: this._seats.map((s) => makeSeatResult(s.seatID, s.results)) };
  }
}
