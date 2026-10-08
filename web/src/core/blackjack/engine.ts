import type { Card, Shoe } from '../cards';
import type { RandomSource } from '../random';
import type { BlackjackHand, HandResult, HandValue } from './hand';
import {
  type BlackjackAction, BlackjackError, type BlackjackEvent, type BlackjackPhase, type BlackjackRules,
} from './rules';
import { BlackjackTableEngine, type BlackjackTableEvent } from './tableEngine';

/**
 * Einzelspieler-Blackjack (Offline). Eine dünne Hülle um `BlackjackTableEngine` mit genau
 * einem Platz – damit gelten offline und online exakt dieselben Regeln aus derselben Implementierung.
 */
export class BlackjackEngine {
  private static readonly seatID = 0;
  private readonly table: BlackjackTableEngine;

  constructor(options: { rules?: BlackjackRules; random: RandomSource }) {
    this.table = new BlackjackTableEngine(options);
  }

  // MARK: - Abfragen

  get rules(): BlackjackRules { return this.table.rules; }
  get shoe(): Shoe { return this.table.shoe; }
  get phase(): BlackjackPhase { return this.table.phase; }
  get dealerCards(): readonly Card[] { return this.table.dealerCards; }
  get isHoleCardRevealed(): boolean { return this.table.isHoleCardRevealed; }
  get dealerVisibleValue(): HandValue { return this.table.dealerVisibleValue; }
  get hands(): readonly BlackjackHand[] { return this.table.seat(BlackjackEngine.seatID)?.hands ?? []; }
  get results(): readonly HandResult[] { return this.table.seat(BlackjackEngine.seatID)?.results ?? []; }
  get activeHandIndex(): number | null { return this.table.turn?.hand ?? null; }
  get activeHand(): BlackjackHand | null { return this.table.currentHand; }
  get totalStake(): number { return this.hands.reduce((s, h) => s + h.bet, 0); }

  /** NUR FÜR TESTS: feste Ziehreihenfolge der nächsten Runde. */
  get testOnlyDeckForNextRound(): Card[] | null { return this.table.testOnlyDeckForNextRound; }
  set testOnlyDeckForNextRound(deck: Card[] | null) { this.table.testOnlyDeckForNextRound = deck; }

  availableActions(): Set<BlackjackAction> {
    return this.table.availableActions(BlackjackEngine.seatID);
  }

  additionalStake(action: BlackjackAction): number {
    return this.table.additionalStake(action, BlackjackEngine.seatID);
  }

  // MARK: - Ablauf

  startRound(bet: number): BlackjackEvent[] {
    return this.table.startRound([{ seatID: BlackjackEngine.seatID, bet }]).map(translate);
  }

  perform(action: BlackjackAction): BlackjackEvent[] {
    if (this.phase !== 'playerTurn') throw BlackjackError.invalidPhase();
    return this.table.perform(action, BlackjackEngine.seatID).map(translate);
  }
}

function translate(event: BlackjackTableEvent): BlackjackEvent {
  switch (event.type) {
    case 'shuffled': return { type: 'shuffled' };
    case 'dealtToPlayer': return { type: 'dealtToPlayer', handID: event.handID, card: event.card };
    case 'dealtToDealer': return { type: 'dealtToDealer', card: event.card, faceDown: event.faceDown };
    case 'holeCardRevealed': return { type: 'holeCardRevealed', card: event.card };
    case 'split':
      return { type: 'split', originalHandID: event.originalHandID, newHandID: event.newHandID, movedCard: event.movedCard };
    case 'doubled': return { type: 'doubled', handID: event.handID };
    case 'turnChanged': return { type: 'activeHandChanged', handID: event.handID };
    case 'settled': return { type: 'settled', results: [...(event.seatResults[0]?.results ?? [])] };
  }
}
