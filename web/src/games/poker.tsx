import { useEffect, useMemo, useState } from 'preact/hooks'
import type { Card } from '../core/cards'
import type { RandomSource } from '../core/random'
import {
  ALL_POKER_STYLES, HandEvaluator, HoldemEngine, PokerAction, PokerAI, PokerAIContext, PokerSeat,
  pokerActionKindTitle, pokerStyleTitle, type PokerEvent, type PokerLegalActions,
} from '../core/poker'
import { Observable, sleep, useObserve } from '../app/observable'
import type { GameHost } from '../app/host'
import { Button, Glass, InfoItem, NoCashValueNote, TableBar, TopBar, useNarrow } from '../ui/components'
import { ChipFormat } from '../ui/format'
import { Dealer, TableCard, TableChips, TablePlane, TableStage } from '../ui/table'
import { RescueHint } from './shared'

// ---------- Tisch-Geometrie ----------

const STAGE_W = 1000
const STAGE_H = 700
const PLANE_TOP = 150
const PLANE_H = 550
const CX = 500
const CY = 262
const RX = 452
const RY = 236
const DECK = { x: 640, y: 54 }
const MUCK = { x: 360, y: 54 }
const POT = { x: 500, y: 356 }
const COMMUNITY_Y = 236

function pick<T>(items: readonly T[], random: RandomSource): T | undefined {
  return items.length ? items[random.uniform(items.length)] : undefined
}

export interface TableOption {
  id: string
  name: string
  smallBlind: number
  bigBlind: number
  minBuyIn: number
  maxBuyIn: number
}

export type PokerStage = 'setup' | 'playing' | 'handOver' | 'busted'

interface CardEntity {
  key: string
  card: Card
  faceUp: boolean
  x: number
  y: number
  rotate: number
  z: number
  width: number
  from?: { x: number; y: number }
  dim?: boolean
}

interface ChipEntity {
  key: number
  amount: number
  x: number
  y: number
  from?: { x: number; y: number }
  gone?: boolean
}

let chipSeq = 1

export interface PokerHandRecord { contributed: number; won: number }

export class PokerViewModel extends Observable {
  static readonly tables: TableOption[] = [
    { id: 'lounge', name: 'Lounge', smallBlind: 10, bigBlind: 20, minBuyIn: 400, maxBuyIn: 2_000 },
    { id: 'highstakes', name: 'High Stakes', smallBlind: 50, bigBlind: 100, minBuyIn: 2_000, maxBuyIn: 10_000 },
    { id: 'vip', name: 'VIP Salon', smallBlind: 250, bigBlind: 500, minBuyIn: 10_000, maxBuyIn: 50_000 },
  ]
  private static readonly names = ['Viktor', 'Lena', 'Marco', 'Sofia', 'Jonas', 'Ava', 'Elias', 'Mila',
    'Noah', 'Clara', 'Leon', 'Ida', 'Felix', 'Nora', 'Theo', 'Lia']
  static readonly humanSeatID = 0

  // Setup
  selectedTable: TableOption
  opponentCount = 4
  buyIn = 1_000

  // Tischzustand (Momentaufnahme für die Anzeige)
  stage: PokerStage = 'setup'
  seats: readonly PokerSeat[] = []
  community: Card[] = []
  pot = 0
  buttonSeatID: number | null = null
  thinkingSeatID: number | null = null
  legal: PokerLegalActions | null = null
  lastActions = new Map<number, string>()
  revealedSeats = new Set<number>()
  showdownHands = new Map<number, string>()
  resultText: string | null = null
  humanWonLastHand = false
  raiseTarget = 0
  winners = new Set<number>()

  // Darstellung
  cards: CardEntity[] = []
  chips: ChipEntity[] = []
  private betChips = new Map<number, number>()
  private seatAngles = new Map<number, number>()

  private engine: HoldemEngine | null = null
  private isRunning = false
  private handWasRecorded = true
  private disposed = false

  constructor(
    private readonly host: GameHost,
    private readonly playerName: () => string,
    private readonly onRecord: (r: PokerHandRecord) => void,
    private readonly setTableEscrow: (amount: number) => void,
    private readonly tableEscrow: () => number,
  ) {
    super()
    // Standard: der kleinste Tisch – höhere Tische wählt man bewusst.
    this.selectedTable = PokerViewModel.tables[0]
    this.buyIn = this.clampedBuyIn(this.selectedTable.maxBuyIn / 2)
  }

  private changed() { if (!this.disposed) this.emit() }
  private wait(ms: number) { return sleep(ms * (this.host.reducedMotion ? 0.55 : 1)) }

  // ---------- Abfragen ----------

  get human(): PokerSeat | undefined { return this.seats.find((s) => s.id === PokerViewModel.humanSeatID) }
  get isHumanTurn(): boolean { return this.legal !== null }
  get bigBlind(): number { return this.engine?.bigBlind ?? this.selectedTable.bigBlind }

  /** Aktuelle beste Hand des Spielers (nur Anzeige). */
  get humanHandName(): string | null {
    const human = this.human
    if (!human || human.holeCards.length !== 2 || this.community.length < 3) return null
    return HandEvaluator.bestHand([...human.holeCards, ...this.community]).name
  }

  clampedBuyIn(value: number): number {
    const t = this.selectedTable
    const maxAffordable = Math.min(t.maxBuyIn, this.host.chips)
    const v = Math.min(Math.max(value, t.minBuyIn), Math.max(t.minBuyIn, maxAffordable))
    return Math.floor(v / t.bigBlind) * t.bigBlind
  }

  get canAffordSelectedTable(): boolean { return this.host.chips >= this.selectedTable.minBuyIn }

  selectTable(option: TableOption) {
    this.selectedTable = option
    this.buyIn = this.clampedBuyIn(option.maxBuyIn / 2)
    this.changed()
  }

  setOpponents(count: number) { this.opponentCount = count; this.changed() }
  setBuyIn(value: number) { this.buyIn = this.clampedBuyIn(value); this.changed() }
  setRaiseTarget(value: number) { this.raiseTarget = value; this.changed() }

  // ---------- Geometrie ----------

  static angles(opponents: number): number[] {
    switch (opponents) {
      case 1: return [90, 200]
      case 2: return [90, 165, 15]
      case 3: return [90, 160, 230, 310]
      default: return [90, 150, 210, 330, 30]
    }
  }

  seatPoint(seatID: number, radius = 1): { x: number; y: number } {
    const a = ((this.seatAngles.get(seatID) ?? 90) * Math.PI) / 180
    return { x: CX + Math.cos(a) * RX * radius, y: CY + Math.sin(a) * RY * radius }
  }

  // ---------- Tisch betreten / verlassen ----------

  async sitDown() {
    if (this.stage !== 'setup') return
    const amount = this.clampedBuyIn(this.buyIn)
    if (amount < this.selectedTable.minBuyIn || !this.host.moveToTable(amount)) return

    const seats = [new PokerSeat({ id: PokerViewModel.humanSeatID, name: this.playerName(), isHuman: true, style: null, stack: amount })]
    const used = new Set<string>()
    for (let id = 1; id <= this.opponentCount; id++) seats.push(this.makeOpponent(id, used))
    this.engine = new HoldemEngine({ seats, smallBlind: this.selectedTable.smallBlind, bigBlind: this.selectedTable.bigBlind, random: this.host.random })
    const angles = PokerViewModel.angles(this.opponentCount)
    this.seatAngles.clear()
    seats.forEach((s, i) => this.seatAngles.set(s.id, angles[i] ?? 90))
    this.seats = this.engine.seats
    this.stage = 'playing'
    this.changed()
    await this.nextHand()
  }

  private makeOpponent(id: number, used: Set<string>): PokerSeat {
    const aux = this.host.auxiliaryRandom
    const name = pick(PokerViewModel.names.filter((n) => !used.has(n)), aux) ?? `KI ${id}`
    used.add(name)
    const style = pick(ALL_POKER_STYLES, aux) ?? 'shark'
    const t = this.selectedTable
    const steps = (t.maxBuyIn - t.minBuyIn) / t.bigBlind
    const stack = t.minBuyIn + aux.uniform(steps + 1) * t.bigBlind
    return new PokerSeat({ id, name, isHuman: false, style, stack })
  }

  /** Verlassen: Restliche Chips gehen zurück aufs Konto. Ein laufender Einsatz gilt als gefoldet. */
  leave() {
    const engine = this.engine
    this.disposed = true
    this.isRunning = false
    if (!engine) return
    const human = engine.seats.find((s) => s.id === PokerViewModel.humanSeatID)
    if (engine.isHandInProgress && !this.handWasRecorded) {
      this.onRecord({ contributed: human?.handContribution ?? 0, won: 0 })
      this.handWasRecorded = true
    }
    this.host.releaseFromTable(this.tableEscrow(), human?.stack ?? 0)
    this.engine = null
    this.stage = 'setup'
  }

  topUp(amount: number) {
    const engine = this.engine
    if (!engine || engine.isHandInProgress || amount <= 0) return
    const index = engine.seats.findIndex((s) => s.id === PokerViewModel.humanSeatID)
    if (index < 0 || !this.host.moveToTable(amount)) return
    try {
      engine.setStack(engine.seats[index].stack + amount, index)
    } catch {
      this.host.releaseFromTable(amount, amount)
      return
    }
    this.seats = engine.seats
    if (this.stage === 'busted') this.stage = 'handOver'
    this.changed()
  }

  // ---------- Spielablauf ----------

  async nextHand() {
    const engine = this.engine
    if (!engine || engine.isHandInProgress || this.isRunning) return
    this.isRunning = true
    try {
      // Ausgeschiedene KI-Gegner werden durch neue ersetzt
      const used = new Set(engine.seats.map((s) => s.name))
      engine.seats.forEach((seat, i) => {
        if (!seat.isHuman && seat.stack === 0) {
          const fresh = this.makeOpponent(seat.id, used)
          engine.replaceSeat(i, fresh)
          this.host.show({ icon: 'userPlus', title: `${fresh.name} nimmt Platz`, subtitle: `Spielstil: ${fresh.style ? pokerStyleTitle(fresh.style) : ''}` })
        }
      })
      if ((engine.seats.find((s) => s.id === PokerViewModel.humanSeatID)?.stack ?? 0) <= 0) {
        this.stage = 'busted'
        this.changed()
        return
      }
      this.stage = 'playing'
      this.resultText = null
      this.humanWonLastHand = false
      this.revealedSeats = new Set()
      this.showdownHands = new Map()
      this.lastActions = new Map()
      this.winners = new Set()
      this.community = []
      this.legal = null
      await this.clearTable()

      let events: PokerEvent[]
      try {
        events = engine.startHand()
      } catch {
        this.host.show({ icon: 'info', title: 'Hand konnte nicht starten', tint: 'red' })
        return
      }
      this.handWasRecorded = false
      this.seats = engine.seats
      await this.play(events)
      await this.runOpponents()
    } finally {
      this.isRunning = false
    }
  }

  /** Lässt die KI-Gegner handeln, bis der Spieler dran ist oder die Hand endet. */
  private async runOpponents() {
    for (;;) {
      const engine = this.engine
      if (!engine || this.disposed || !engine.isHandInProgress) break
      const index = engine.currentIndex
      if (index === null) break
      const seat = engine.seats[index]
      if (seat.isHuman) {
        this.thinkingSeatID = null
        this.legal = engine.legalActions(index)
        if (this.legal) this.raiseTarget = this.legal.minRaiseTo
        this.changed()
        return
      }
      this.thinkingSeatID = seat.id
      this.changed()
      // Natürliche Bedenkzeit (rein optisch)
      await this.wait(550 + this.host.auxiliaryRandom.unitDouble() * 800)
      if (this.engine !== engine || engine.currentIndex !== index) return

      // Die KI sieht nur ihre eigenen Karten und das Board; ihr Zufall dient nur dem Spielstil.
      const context = new PokerAIContext(engine, index)
      const action = PokerAI.decide(context, seat.style ?? 'shark', this.host.auxiliaryRandom)
      let events: PokerEvent[]
      try {
        events = engine.apply(action, index)
      } catch {
        // Sicherheitsnetz: nie hängen bleiben
        const fallback = engine.legalActions(index)?.canCheck ? PokerAction.check : PokerAction.fold
        try { events = engine.apply(fallback, index) } catch { events = [] }
      }
      this.thinkingSeatID = null
      await this.play(events)
    }
    const engine = this.engine
    if (engine && !engine.isHandInProgress) this.finishHand(engine)
  }

  async act(action: PokerAction) {
    const engine = this.engine
    if (!engine || !this.legal) return
    const index = engine.currentIndex
    if (index === null || !engine.seats[index].isHuman) return
    this.legal = null
    this.changed()
    let events: PokerEvent[]
    try {
      events = engine.apply(action, index)
    } catch {
      this.legal = engine.legalActions(index)
      this.changed()
      return
    }
    await this.play(events)
    await this.runOpponents()
  }

  async confirmRaise() {
    const legal = this.legal
    if (!legal) return
    const target = Math.round(this.raiseTarget)
    if (target >= legal.maxRaiseTo) await this.act(PokerAction.allIn)
    else await this.act(PokerAction.raise(Math.max(target, legal.minRaiseTo)))
  }

  /** Setzt den Regler auf einen Anteil des Pots. */
  setRaise(potFraction: number) {
    const legal = this.legal
    const engine = this.engine
    if (!legal || !engine) return
    const target = engine.currentBet + Math.floor((engine.pot + legal.callAmount) * potFraction)
    this.raiseTarget = Math.min(Math.max(target, legal.minRaiseTo), legal.maxRaiseTo)
    this.changed()
  }

  private finishHand(engine: HoldemEngine) {
    const human = engine.seats.find((s) => s.id === PokerViewModel.humanSeatID)
    if (this.handWasRecorded || !human) return
    this.handWasRecorded = true
    this.seats = engine.seats
    this.pot = 0
    const won = engine.lastAwards.filter((a) => a.seatID === PokerViewModel.humanSeatID).reduce((s, a) => s + a.amount, 0)
    if (!human.isSittingOut) this.onRecord({ contributed: human.handContribution, won })
    this.setTableEscrow(human.stack)
    this.humanWonLastHand = won > 0
    this.resultText = engine.lastAwards.map((award) => {
      const name = engine.seats.find((s) => s.id === award.seatID)?.name ?? '?'
      const hand = award.handName ? ` mit ${award.handName}` : ''
      return `${award.seatID === PokerViewModel.humanSeatID ? 'Du gewinnst' : `${name} gewinnt`} ${ChipFormat.string(award.amount)}${hand}`
    }).join('\n')
    this.stage = human.stack === 0 ? 'busted' : 'handOver'
    this.changed()
  }

  // ---------- Darstellung der Ereignisse ----------

  private async clearTable() {
    this.cards = this.cards.map((c, i) => ({ ...c, x: MUCK.x, y: MUCK.y - i * 0.3, faceUp: false, rotate: 80, from: undefined, z: 40 + i }))
    this.chips = this.chips.map((c) => ({ ...c, gone: true }))
    this.changed()
    if (this.cards.length) await this.wait(450)
    this.cards = []
    this.chips = []
    this.betChips.clear()
    this.changed()
  }

  private async setBet(seatID: number, amount: number) {
    const target = this.seatPoint(seatID, 0.5)
    const existing = this.betChips.get(seatID)
    if (existing !== undefined) {
      this.chips = this.chips.map((c) => (c.key === existing ? { ...c, amount } : c))
      this.changed()
      await this.wait(260)
      return
    }
    const key = chipSeq++
    this.betChips.set(seatID, key)
    this.chips = [...this.chips, { key, amount, x: target.x, y: target.y, from: this.seatPoint(seatID, 0.95) }]
    this.changed()
    await this.wait(380)
  }

  private async collectBets(total: number) {
    this.chips = this.chips.map((c) => ({ ...c, x: POT.x, y: POT.y, gone: c.key !== -1 }))
    this.changed()
    await this.wait(420)
    this.chips = [{ key: -1, amount: total, x: POT.x, y: POT.y }]
    this.betChips.clear()
    this.changed()
  }

  private holeCardPos(seatID: number, index: number) {
    if (seatID === PokerViewModel.humanSeatID) {
      const p = this.seatPoint(seatID, 0.78)
      return { x: p.x - 34 + index * 70, y: p.y - 6, rotate: index === 0 ? -5 : 5, width: 104 }
    }
    const p = this.seatPoint(seatID, 0.74)
    return { x: p.x - 16 + index * 32, y: p.y, rotate: index === 0 ? -7 : 6, width: 68 }
  }

  private async play(events: PokerEvent[]) {
    const engine = this.engine
    if (!engine) return
    for (let i = 0; i < events.length; i++) {
      if (this.disposed) return
      const event = events[i]
      switch (event.type) {
        case 'handStarted':
          this.buttonSeatID = event.buttonSeatID
          this.changed()
          break

        case 'blindPosted':
          this.lastActions.set(event.seatID, (event.isBig ? 'BB ' : 'SB ') + ChipFormat.compact(event.amount))
          await this.setBet(event.seatID, event.amount)
          break

        case 'holeCardsDealt': {
          // Alle Ausgaben einsammeln und klassisch reihum (je eine Karte) austeilen
          const deals: Array<{ seatID: number; cards: readonly Card[] }> = []
          while (i < events.length && events[i].type === 'holeCardsDealt') {
            const e = events[i] as Extract<PokerEvent, { type: 'holeCardsDealt' }>
            deals.push({ seatID: e.seatID, cards: e.cards })
            i++
          }
          i--
          for (let round = 0; round < 2; round++) {
            for (const deal of deals) {
              if (deal.cards.length <= round) continue
              const pos = this.holeCardPos(deal.seatID, round)
              const isHuman = deal.seatID === PokerViewModel.humanSeatID
              this.cards = [...this.cards, {
                key: `h${deal.seatID}-${round}`, card: deal.cards[round], faceUp: isHuman,
                x: pos.x, y: pos.y, rotate: pos.rotate, width: pos.width, z: round + 1, from: DECK,
              }]
              this.changed()
              await this.wait(isHuman ? 300 : 190)
            }
          }
          this.seats = engine.seats
          this.changed()
          break
        }

        case 'action': {
          const kind = event.record.kind
          this.lastActions.set(event.seatID, kind === 'fold' || kind === 'check'
            ? pokerActionKindTitle(kind)
            : `${pokerActionKindTitle(kind)} ${ChipFormat.compact(event.record.streetTotal)}`)
          this.seats = engine.seats
          if (kind === 'fold') {
            this.cards = this.cards.map((c) => (c.key.startsWith(`h${event.seatID}-`)
              ? { ...c, x: MUCK.x, y: MUCK.y, faceUp: false, rotate: 70, from: undefined, z: 30 } : c))
            this.changed()
            await this.wait(360)
          } else if (kind !== 'check') {
            await this.setBet(event.seatID, event.record.streetTotal)
          } else {
            this.changed()
            await this.wait(220)
          }
          break
        }

        case 'betsCollected':
          this.pot = event.pot
          await this.collectBets(event.pot)
          break

        case 'communityDealt': {
          // Neue Setzrunde: Aktionsanzeigen zurücksetzen (Folds bleiben sichtbar)
          for (const [id, text] of [...this.lastActions]) if (text !== 'Fold') this.lastActions.delete(id)
          const start = this.community.length
          for (let k = 0; k < event.cards.length; k++) {
            const index = start + k
            this.cards = [...this.cards, {
              key: `c${index}`, card: event.cards[k], faceUp: true,
              x: CX + (index - 2) * 104, y: COMMUNITY_Y, rotate: 0, width: 92, z: 1, from: DECK,
            }]
            this.community = [...this.community, event.cards[k]]
            this.changed()
            await this.wait(260)
          }
          await this.wait(200)
          break
        }

        case 'showdown':
          for (const entry of event.entries) {
            this.revealedSeats.add(entry.seatID)
            this.showdownHands.set(entry.seatID, entry.hand.name)
            this.cards = this.cards.map((c) => (c.key.startsWith(`h${entry.seatID}-`) ? { ...c, faceUp: true, from: undefined } : c))
            this.changed()
            await this.wait(380)
          }
          this.seats = engine.seats
          this.changed()
          await this.wait(800)
          break

        case 'potAwarded': {
          this.winners.add(event.award.seatID)
          const target = this.seatPoint(event.award.seatID, 0.95)
          const key = chipSeq++
          this.chips = this.chips.filter((c) => c.key !== -1)
          this.chips = [...this.chips, { key, amount: event.award.amount, x: target.x, y: target.y, from: POT, gone: false }]
          const remaining = events.slice(i + 1).some((e) => e.type === 'potAwarded')
          this.changed()
          await this.wait(620)
          this.chips = this.chips.map((c) => (c.key === key ? { ...c, gone: true } : c))
          if (!remaining) this.pot = 0
          this.changed()
          break
        }

        case 'handFinished':
          break
      }
    }
    if (engine.isHandInProgress) {
      this.seats = engine.seats
      this.pot = engine.pot
      this.changed()
    }
  }
}

// ---------- Darstellung ----------

function PokerTableView({ vm }: { vm: PokerViewModel }) {
  useObserve(vm)
  const showdownBest = (seatID: number) => vm.winners.has(seatID)
  return (
    <TableStage width={STAGE_W} height={STAGE_H} padTop={70}>
      <Dealer x={STAGE_W / 2} y={PLANE_TOP + 66} width={250} />
      <TablePlane kind="pk" top={PLANE_TOP} height={PLANE_H} tilt={34} print={<PokerPrint />}>
        <div class="shoe" style={{ left: DECK.x - 40, top: DECK.y - 24, width: 80, height: 50, transform: 'rotate(-8deg)' }} />
        {vm.pot > 0 && <div class="felt-label" style={{ left: POT.x, top: POT.y + 44 }}>Pot {ChipFormat.string(vm.pot)}</div>}
        {vm.chips.map((c) => (
          <div key={c.key} style={{ opacity: c.gone ? 0 : 1, transition: 'opacity .4s ease .25s' }}>
            <TableChips amount={c.amount} x={c.x} y={c.y} from={c.from} width={52} />
          </div>
        ))}
        {vm.cards.map((c) => (
          <TableCard key={c.key} card={c.faceUp ? { rank: c.card.rank, suit: c.card.suit } : null}
            x={c.x} y={c.y} rotate={c.rotate} z={c.z} from={c.from} width={c.width} />
        ))}
        {vm.seats.filter((s) => !s.isHuman).map((seat) => {
          const p = vm.seatPoint(seat.id, 1.02)
          const action = vm.lastActions.get(seat.id)
          const revealed = vm.revealedSeats.has(seat.id) ? vm.showdownHands.get(seat.id) : undefined
          return (
            <div class={`seat-plate ${vm.thinkingSeatID === seat.id ? 'turn' : ''} ${seat.hasFolded ? 'folded' : ''}`}
              style={{ left: p.x, top: p.y, borderColor: showdownBest(seat.id) ? 'rgba(247,222,158,.9)' : undefined }}>
              {vm.buttonSeatID === seat.id && <div class="dealer-btn">D</div>}
              <b>{seat.name}</b>
              <span>{ChipFormat.string(seat.stack)}</span>
              <small style={revealed ? { color: 'var(--gold)' } : undefined}>
                {vm.thinkingSeatID === seat.id ? 'überlegt …' : revealed ?? action ?? (seat.style ? pokerStyleTitle(seat.style) : '')}
              </small>
            </div>
          )
        })}
        {vm.buttonSeatID === PokerViewModel.humanSeatID && (() => {
          const p = vm.seatPoint(PokerViewModel.humanSeatID, 0.8)
          return <div class="seat-plate" style={{ left: p.x + 150, top: p.y, minWidth: 0, padding: 0, width: 38, height: 38, borderRadius: 19, background: 'linear-gradient(#fff,#ddd)', color: '#111', fontWeight: 900, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>D</div>
        })()}
      </TablePlane>
    </TableStage>
  )
}

function PokerPrint() {
  return (
    <svg viewBox="0 0 940 490" width="100%" height="100%" preserveAspectRatio="none" style={{ position: 'absolute', inset: 0 }}>
      <rect x="40" y="40" width="860" height="410" rx="205" fill="none" stroke="rgba(240,228,196,.16)" stroke-width="2" />
      <text x="470" y="330" text-anchor="middle" fill="rgba(240,228,196,.22)" font-size="22" letter-spacing="8" font-family="Georgia, serif" font-weight="700">BLACKCASINO</text>
    </svg>
  )
}

function PokerSetup({ vm, chips, onRescue, canClaimRescue }: { vm: PokerViewModel; chips: number; onRescue: () => void; canClaimRescue: boolean }) {
  useObserve(vm)
  const t = vm.selectedTable
  const maxBuy = Math.max(t.minBuyIn + 1, Math.min(t.maxBuyIn, chips))
  return (
    <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, zIndex: 20, overflowY: 'auto' }}>
      <Glass radius={32} style={{ width: 'min(820px, 100%)', padding: 'clamp(20px, 4vw, 32px)', display: 'flex', flexDirection: 'column', gap: 24, animation: 'rise .4s ease-out' }}>
        <div>
          <h2 class="display" style={{ margin: 0, fontSize: 28 }}>TISCH WÄHLEN</h2>
          <div style={{ fontSize: 15, color: 'var(--text-2)', marginTop: 4 }}>Texas Hold'em gegen KI-Gegner mit eigenen Spielstilen</div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14 }}>
          {PokerViewModel.tables.map((option) => {
            const affordable = chips >= option.minBuyIn
            const selected = vm.selectedTable.id === option.id
            return (
              <button disabled={!affordable} onClick={() => vm.selectTable(option)}
                style={{
                  textAlign: 'left', padding: 18, borderRadius: 20, opacity: affordable ? 1 : 0.4,
                  background: selected ? 'var(--red-gradient)' : 'var(--surface-raised)',
                  border: `1px solid ${selected ? 'rgba(247,222,158,.6)' : 'var(--stroke)'}`,
                }}>
                <div class="display" style={{ fontSize: 17 }}>{option.name.toUpperCase()}</div>
                <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--gold-light)', marginTop: 6 }}>Blinds {option.smallBlind}/{option.bigBlind}</div>
                <div style={{ fontSize: 13, color: 'var(--text-2)', marginTop: 4 }}>Buy-in {ChipFormat.compact(option.minBuyIn)}–{ChipFormat.compact(option.maxBuyIn)}</div>
              </button>
            )
          })}
        </div>
        <div style={{ display: 'flex', gap: 30, flexWrap: 'wrap' }}>
          <div>
            <div class="label-caps">GEGNER</div>
            <div class="segmented">
              {[1, 2, 3, 4].map((n) => <button class={vm.opponentCount === n ? 'on' : ''} onClick={() => vm.setOpponents(n)}>{n}</button>)}
            </div>
          </div>
          <div style={{ flex: 1, minWidth: 220 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <div class="label-caps">BUY-IN</div>
              <div class="numeric" style={{ fontSize: 20, fontWeight: 900 }}>{ChipFormat.string(vm.clampedBuyIn(vm.buyIn))}</div>
            </div>
            <input type="range" class="slider" min={t.minBuyIn} max={maxBuy} step={t.bigBlind} value={vm.buyIn}
              onInput={(e) => vm.setBuyIn(Number((e.target as HTMLInputElement).value))} />
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap', position: 'relative' }}>
          <NoCashValueNote compact />
          <span style={{ flex: 1 }} />
          {!vm.canAffordSelectedTable && <RescueHint onClaim={onRescue} canClaim={canClaimRescue} />}
          <Button kind="primary" size="large" disabled={!vm.canAffordSelectedTable} onClick={() => vm.sitDown()}>PLATZ NEHMEN</Button>
        </div>
      </Glass>
    </div>
  )
}

function PokerControls({ vm, chips }: { vm: PokerViewModel; chips: number }) {
  useObserve(vm)
  const narrow = useNarrow(1000)
  if (vm.stage === 'handOver') {
    return (
      <div class="controls-row" style={{ justifyContent: 'flex-end' }}>
        <Button kind="secondary" size="large" style={{ flex: '0 1 auto' }} disabled={chips < vm.selectedTable.minBuyIn} onClick={() => vm.topUp(vm.selectedTable.minBuyIn)}>AUFSTOCKEN</Button>
        <Button kind="primary" size="large" style={{ flex: '0 1 auto' }} onClick={() => vm.nextHand()}>NÄCHSTE HAND</Button>
      </div>
    )
  }
  if (vm.stage === 'busted') {
    return (
      <div class="controls-row" style={{ justifyContent: 'flex-end' }}>
        <Button kind="gold" size="large" style={{ flex: '0 1 auto' }} disabled={chips < vm.selectedTable.minBuyIn} onClick={() => vm.topUp(vm.selectedTable.minBuyIn)}>
          NACHKAUFEN · {ChipFormat.string(vm.selectedTable.minBuyIn)}
        </Button>
      </div>
    )
  }
  const legal = vm.legal
  if (!legal) {
    return <div style={{ height: 64, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', color: 'var(--text-2)', fontWeight: 600 }}>
      {vm.thinkingSeatID !== null ? 'Gegner überlegt …' : ''}
    </div>
  }
  const target = Math.round(vm.raiseTarget)
  const isAllIn = target >= legal.maxRaiseTo
  const stack = vm.human?.stack ?? 0
  const raiseRow = legal.canRaise && legal.maxRaiseTo > legal.minRaiseTo && (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center', flex: narrow ? undefined : '1 1 auto', minWidth: 0 }}>
      <Button kind="ghost" size="small" onClick={() => vm.setRaiseTarget(legal.minRaiseTo)}>MIN</Button>
      <Button kind="ghost" size="small" onClick={() => vm.setRaise(0.5)}>½ POT</Button>
      <Button kind="ghost" size="small" onClick={() => vm.setRaise(1)}>POT</Button>
      <input type="range" class="slider" style={{ flex: 1, minWidth: 120 }} min={legal.minRaiseTo} max={legal.maxRaiseTo}
        step={Math.max(1, Math.min(vm.bigBlind, legal.maxRaiseTo - legal.minRaiseTo))} value={vm.raiseTarget}
        onInput={(e) => vm.setRaiseTarget(Number((e.target as HTMLInputElement).value))} />
    </div>
  )
  const buttons = (
    <div style={{ display: 'flex', gap: 12, flex: narrow ? undefined : 'none' }}>
      <Button kind="secondary" size="large" style={narrow ? { flex: 1, padding: '0 10px' } : undefined} onClick={() => vm.act(PokerAction.fold)}>FOLD</Button>
      {legal.canCheck
        ? <Button kind="secondary" size="large" style={narrow ? { flex: 1, padding: '0 10px' } : undefined} onClick={() => vm.act(PokerAction.check)}>CHECK</Button>
        : <Button kind="secondary" size="large" style={narrow ? { flex: 1, padding: '0 10px' } : undefined} onClick={() => vm.act(PokerAction.call)}>
            {legal.callAmount >= stack ? `ALL-IN ${ChipFormat.string(legal.callAmount)}` : `CALL ${ChipFormat.string(legal.callAmount)}`}
          </Button>}
      {legal.canRaise && (
        <Button kind="primary" size="large" style={narrow ? { flex: 1.3, padding: '0 10px' } : undefined} onClick={() => vm.confirmRaise()}>
          {isAllIn ? `ALL-IN ${ChipFormat.string(legal.maxRaiseTo)}` : `${legal.canCheck ? 'BET' : 'RAISE'} ${ChipFormat.string(target)}`}
        </Button>
      )}
    </div>
  )
  return narrow
    ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{raiseRow}{buttons}</div>
    : <div style={{ display: 'flex', gap: 14, alignItems: 'center', justifyContent: 'flex-end' }}>{raiseRow}{buttons}</div>
}

function PokerInfo({ vm, chips }: { vm: PokerViewModel; chips: number }) {
  useObserve(vm)
  const human = vm.human
  const handName = vm.humanHandName
  const last = vm.lastActions.get(PokerViewModel.humanSeatID)
  const firstLine = vm.resultText?.split('\n')[0]
  return (
    <>
      <InfoItem title="Virtuelle Chips" value={ChipFormat.string(chips)} />
      <InfoItem title="Dein Stack" value={ChipFormat.string(human?.stack ?? 0)} />
      <InfoItem title="Einsatz" value={ChipFormat.string(human?.streetBet ?? 0)} />
      <InfoItem title="Pot" value={ChipFormat.string(vm.pot)} />
      {handName && human && !human.hasFolded && <InfoItem title="Deine Hand" value={handName} color="var(--gold-light)" />}
      {last && <InfoItem title="Letzte Aktion" value={last} />}
      {firstLine && vm.stage !== 'playing' && (
        <div class="result-pill" style={{ color: vm.humanWonLastHand ? 'var(--gold-light)' : 'var(--text-2)', borderColor: vm.humanWonLastHand ? 'rgba(212,173,102,.6)' : undefined }}>
          {firstLine}
        </div>
      )}
    </>
  )
}

export function PokerScreen({ host, chips, playerName, tableEscrow, setTableEscrow, onLeave, onRules, onHelp, onRecord, onRescue, canClaimRescue }: {
  host: GameHost
  chips: number
  playerName: () => string
  tableEscrow: () => number
  setTableEscrow: (amount: number) => void
  onLeave: () => void
  onRules: () => void
  onHelp: () => void
  onRecord: (r: PokerHandRecord) => void
  onRescue: () => void
  canClaimRescue: boolean
}) {
  const vm = useMemo(() => new PokerViewModel(host, playerName, onRecord, setTableEscrow, tableEscrow), [])
  const [, setTick] = useState(0)
  useEffect(() => vm.subscribe(() => setTick((n) => n + 1)), [])
  useEffect(() => () => vm.leave(), [])
  return (
    <div class="screen" style={{ display: 'flex', flexDirection: 'column', background: '#000' }}>
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex' }}>
        <PokerTableView vm={vm} />
        <TopBar title="TEXAS HOLD'EM" subtitle={`No Limit · Blinds ${vm.selectedTable.smallBlind}/${vm.selectedTable.bigBlind}`}
          onLeave={() => { vm.leave(); onLeave() }} onRules={onRules} onHelp={onHelp} />
        {vm.stage === 'setup' && <PokerSetup vm={vm} chips={chips} onRescue={onRescue} canClaimRescue={canClaimRescue} />}
      </div>
      {vm.stage !== 'setup' && (
        <TableBar info={<PokerInfo vm={vm} chips={chips} />}>
          <PokerControls vm={vm} chips={chips} />
        </TableBar>
      )}
    </div>
  )
}
