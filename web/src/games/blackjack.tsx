import { useEffect, useMemo, useState } from 'preact/hooks'
import { BlackjackEngine, HandValue, handOutcomeTitle, makeBlackjackRules, type BlackjackAction, type BlackjackEvent, type HandResult } from '../core/blackjack'
import type { Card } from '../core/cards'
import { Observable, sleep, useObserve } from '../app/observable'
import type { GameHost } from '../app/host'
import { Button, InfoItem, ResultPill, TableBar, TopBar, useNarrow } from '../ui/components'
import { Icon, type IconName } from '../ui/icons'
import { ChipFormat } from '../ui/format'
import { CARD_UNIT_W, Dealer, Shoe, TableCard, TableChips, TablePlane, TableStage } from '../ui/table'
import { ChipSelector, RescueHint } from './shared'

// ---------- Tisch-Geometrie (Koordinaten der Tischfläche) ----------

const STAGE_W = 1000
const STAGE_H = 700
const PLANE_TOP = 238
const PLANE_H = 462
const SHOE = { x: 880, y: 70 }
const DISCARD = { x: 118, y: 66 }
const DEALER_TRAY = { x: 500, y: 26 }
const DEALER_ROW_Y = 104
const HAND_Y = 296
const BET_Y = 414
const PLAYER_EDGE_Y = 520

interface CardEntity {
  key: number
  card: Card
  faceUp: boolean
  x: number
  y: number
  rotate: number
  z: number
  from?: { x: number; y: number }
}

interface ChipEntity {
  key: number
  amount: number
  x: number
  y: number
  from?: { x: number; y: number }
  gone?: boolean
}

export interface VisibleHand {
  id: number
  cards: Card[]
  bet: number
  isActive: boolean
  result?: HandResult
  doubled: boolean
}

export type BlackjackStage = 'betting' | 'busy' | 'playerTurn' | 'roundOver'

let entitySeq = 1

/**
 * Verbindet Engine (Regeln), Tischdarstellung und App-Modell (Chips/Fortschritt).
 * Die Engine entscheidet alles; die Darstellung spielt ihre Ereignisse nur nach.
 */
export class BlackjackViewModel extends Observable {
  static readonly chipValues = [5, 25, 100, 500, 1_000, 5_000]
  /** Regelwerk dieses Tisches (wird auch im „Rules“-Bereich angezeigt). */
  static readonly tableRules = makeBlackjackRules({ minBet: 10, maxBet: 10_000 })

  readonly rules = BlackjackViewModel.tableRules
  private readonly engine: BlackjackEngine

  stage: BlackjackStage = 'betting'
  pendingBet = 0
  lastBet = 0
  hands: VisibleHand[] = []
  dealerCards: Card[] = []
  holeHidden = false
  actions = new Set<BlackjackAction>()
  summary: { title: string; net: number } | null = null
  dealerReaching = false

  // Darstellung
  cards: CardEntity[] = []
  chips: ChipEntity[] = []
  private handOrder: number[] = []
  readonly playerCardKeys = new Map<number, number[]>()
  private dealerCardKeys: number[] = []
  private betChipKeys = new Map<number, number>()
  private roundCredited = true
  private disposed = false

  constructor(private readonly host: GameHost, private readonly onRecord: (r: BlackjackRoundRecord) => void) {
    super()
    this.engine = new BlackjackEngine({ rules: this.rules, random: host.random })
    this.pendingBet = Math.min(100, Math.max(this.rules.minBet, host.chips))
  }

  private get pace(): number { return this.host.reducedMotion ? 0.55 : 1 }
  private wait(ms: number) { return sleep(ms * this.pace) }
  private changed() { if (!this.disposed) this.emit() }

  // ---------- Anzeige ----------

  get dealerValueText(): string | null {
    if (this.dealerCards.length === 0) return null
    const visible = this.holeHidden ? this.dealerCards.slice(0, 1) : this.dealerCards
    return HandValue.display(HandValue.of(visible))
  }

  canAfford(action: BlackjackAction): boolean {
    return this.engine.additionalStake(action) <= this.host.chips
  }

  // ---------- Einsatz ----------

  addChip(value: number) {
    if (this.stage !== 'betting' && this.stage !== 'roundOver') return
    const target = Math.min(this.pendingBet + value, this.rules.maxBet, this.host.chips)
    if (target === this.pendingBet) return
    this.pendingBet = target
    this.changed()
  }

  clearBet() {
    this.pendingBet = 0
    this.changed()
  }

  repeatLastBet() {
    if (this.lastBet <= 0) return
    this.pendingBet = Math.min(this.lastBet, this.host.chips, this.rules.maxBet)
    this.changed()
  }

  // ---------- Ablauf ----------

  async deal() {
    if (this.stage !== 'betting' && this.stage !== 'roundOver') return
    if (this.stage === 'roundOver') await this.resetTable()
    if (this.pendingBet < this.rules.minBet) {
      this.host.show({ icon: 'info', title: `Mindesteinsatz ${this.rules.minBet}`, tint: 'red' })
      return
    }
    const bet = this.pendingBet
    if (!this.host.moveToTable(bet)) return

    this.stage = 'busy'
    this.lastBet = bet
    this.summary = null
    this.roundCredited = false
    this.hands = [{ id: 0, cards: [], bet, isActive: false, doubled: false }]
    this.changed()
    await this.placeBet(0, bet)

    let events: BlackjackEvent[]
    try {
      events = this.engine.startRound(bet)
    } catch {
      this.host.releaseFromTable(bet, bet)
      this.roundCredited = true
      this.stage = 'betting'
      this.changed()
      return
    }
    await this.play(events)
  }

  async perform(action: BlackjackAction) {
    if (this.stage !== 'playerTurn' || !this.actions.has(action)) return
    const extra = this.engine.additionalStake(action)
    if (extra > 0 && !this.host.moveToTable(extra)) return
    this.stage = 'busy'
    this.changed()
    let events: BlackjackEvent[]
    try {
      events = this.engine.perform(action)
    } catch {
      if (extra > 0) this.host.releaseFromTable(extra, extra)
      this.stage = 'playerTurn'
      this.changed()
      return
    }
    await this.play(events)
  }

  async newRound() {
    await this.resetTable()
    this.pendingBet = Math.min(this.lastBet, this.host.chips, this.rules.maxBet)
    this.changed()
  }

  /** Beim Verlassen: offene Hände werden regelkonform mit „Stand“ beendet und abgerechnet. */
  leave() {
    while (this.engine.phase === 'playerTurn') {
      try {
        this.engine.perform('stand')
      } catch {
        break
      }
    }
    if (this.engine.phase === 'settled') this.credit(this.engine.results)
    this.disposed = true
  }

  private async resetTable() {
    this.stage = 'busy'
    this.summary = null
    // Karten in den Ablagestapel
    this.cards = this.cards.map((c, i) => ({ ...c, x: DISCARD.x + (i % 3), y: DISCARD.y - i * 0.4, rotate: 90, faceUp: false, z: 30 + i, from: undefined }))
    this.chips = this.chips.map((c) => ({ ...c, gone: true }))
    this.changed()
    await this.wait(480)
    this.cards = []
    this.chips = []
    this.hands = []
    this.dealerCards = []
    this.holeHidden = false
    this.actions = new Set()
    this.handOrder = []
    this.playerCardKeys.clear()
    this.dealerCardKeys = []
    this.betChipKeys.clear()
    this.stage = 'betting'
    this.changed()
  }

  // ---------- Positionen ----------

  private handCenterX(index: number, count: number): number {
    const spacing = count >= 4 ? 228 : count === 3 ? 262 : 290
    return STAGE_W / 2 + (index - (count - 1) / 2) * spacing
  }

  private cardPos(handID: number, cardIndex: number, rotated: boolean) {
    const index = Math.max(0, this.handOrder.indexOf(handID))
    const cx = this.handCenterX(index, Math.max(1, this.handOrder.length))
    // Wie am echten Tisch: jede Karte leicht versetzt, damit alle Werte sichtbar bleiben.
    return {
      x: cx - 14 + cardIndex * 30,
      y: HAND_Y - cardIndex * 22 + (rotated ? 10 : 0),
      rotate: rotated ? 90 : 0,
      z: cardIndex + 1,
    }
  }

  private betPos(handID: number) {
    const index = Math.max(0, this.handOrder.indexOf(handID))
    return { x: this.handCenterX(index, Math.max(1, this.handOrder.length)), y: BET_Y }
  }

  private dealerPos(index: number) {
    return { x: STAGE_W / 2 - 42 + index * (CARD_UNIT_W * 0.86), y: DEALER_ROW_Y, rotate: 0, z: index + 1 }
  }

  private relayout() {
    const doubled = new Set(this.hands.filter((h) => h.doubled).map((h) => h.id))
    for (const id of this.handOrder) {
      const keys = this.playerCardKeys.get(id) ?? []
      keys.forEach((key, i) => {
        const pos = this.cardPos(id, i, doubled.has(id) && i === 2)
        this.cards = this.cards.map((c) => (c.key === key ? { ...c, ...pos, from: undefined } : c))
      })
      const chipKey = this.betChipKeys.get(id)
      if (chipKey !== undefined) {
        const p = this.betPos(id)
        this.chips = this.chips.map((c) => (c.key === chipKey ? { ...c, x: p.x, y: p.y, from: undefined } : c))
      }
    }
  }

  // ---------- Einsätze ----------

  /** Chips gleiten vom Spielerplatz ins Einsatzfeld. */
  private async placeBet(handID: number, amount: number) {
    if (!this.handOrder.includes(handID)) this.handOrder.push(handID)
    const p = this.betPos(handID)
    const key = entitySeq++
    this.betChipKeys.set(handID, key)
    this.chips = [...this.chips, { key, amount, x: p.x, y: p.y, from: { x: p.x, y: PLAYER_EDGE_Y } }]
    this.changed()
    await this.wait(380)
  }

  /** Zusätzliche Chips (Double) gleiten auf den bestehenden Stapel. */
  private async updateBet(handID: number, amount: number) {
    const key = this.betChipKeys.get(handID)
    if (key === undefined) return
    const p = this.betPos(handID)
    const incoming = entitySeq++
    const existing = this.chips.find((c) => c.key === key)
    const extra = amount - (existing?.amount ?? 0)
    if (extra <= 0) return
    this.chips = [...this.chips, { key: incoming, amount: extra, x: p.x + 4, y: p.y - 6, from: { x: p.x, y: PLAYER_EDGE_Y } }]
    this.changed()
    await this.wait(400)
    this.chips = this.chips.filter((c) => c.key !== incoming).map((c) => (c.key === key ? { ...c, amount } : c))
    this.changed()
  }

  // ---------- Ereignisse abspielen ----------

  private async reach() {
    this.dealerReaching = true
    this.changed()
    window.setTimeout(() => { this.dealerReaching = false; this.changed() }, 300 * this.pace)
  }

  private async play(events: BlackjackEvent[]) {
    for (const event of events) {
      if (this.disposed) return
      switch (event.type) {
        case 'shuffled':
          // Jede Runde beginnt mit einem frisch gemischten Deck – nichts anzuzeigen.
          break

        case 'dealtToPlayer': {
          const hand = this.hands.find((h) => h.id === event.handID)
          const keys = this.playerCardKeys.get(event.handID) ?? []
          const pos = this.cardPos(event.handID, keys.length, !!hand?.doubled && keys.length === 2)
          const key = entitySeq++
          keys.push(key)
          this.playerCardKeys.set(event.handID, keys)
          this.cards = [...this.cards, { key, card: event.card, faceUp: true, ...pos, from: SHOE }]
          this.hands = this.hands.map((h) => (h.id === event.handID ? { ...h, cards: [...h.cards, event.card] } : h))
          this.reach()
          this.changed()
          await this.wait(560)
          break
        }

        case 'dealtToDealer': {
          const pos = this.dealerPos(this.dealerCardKeys.length)
          const key = entitySeq++
          this.dealerCardKeys.push(key)
          this.cards = [...this.cards, { key, card: event.card, faceUp: !event.faceDown, ...pos, from: SHOE }]
          this.dealerCards = [...this.dealerCards, event.card]
          if (event.faceDown) this.holeHidden = true
          this.reach()
          this.changed()
          await this.wait(520)
          break
        }

        case 'holeCardRevealed': {
          const key = this.dealerCardKeys[1]
          this.cards = this.cards.map((c) => (c.key === key ? { ...c, faceUp: true, from: undefined } : c))
          this.holeHidden = false
          this.changed()
          await this.wait(700)
          break
        }

        case 'split': {
          const i = this.hands.findIndex((h) => h.id === event.originalHandID)
          if (i >= 0) {
            const original = this.hands[i]
            const cards = [...original.cards]
            if (cards.length && cards[cards.length - 1].id === event.movedCard.id) cards.pop()
            const next = [...this.hands]
            next[i] = { ...original, cards }
            next.splice(i + 1, 0, { id: event.newHandID, cards: [event.movedCard], bet: original.bet, isActive: false, doubled: false })
            this.hands = next
          }
          const orderIndex = this.handOrder.indexOf(event.originalHandID)
          this.handOrder.splice(orderIndex + 1, 0, event.newHandID)
          const keys = this.playerCardKeys.get(event.originalHandID) ?? []
          const moved = keys.pop()
          this.playerCardKeys.set(event.originalHandID, keys)
          this.playerCardKeys.set(event.newHandID, moved !== undefined ? [moved] : [])
          this.relayout()
          this.changed()
          await this.wait(420)
          const amount = this.hands.find((h) => h.id === event.originalHandID)?.bet ?? 0
          await this.placeBet(event.newHandID, amount)
          this.relayout()
          this.changed()
          break
        }

        case 'doubled': {
          const hand = this.hands.find((h) => h.id === event.handID)
          if (hand) {
            this.hands = this.hands.map((h) => (h.id === event.handID ? { ...h, bet: h.bet * 2, doubled: true } : h))
            this.changed()
            await this.updateBet(event.handID, hand.bet * 2)
          }
          break
        }

        case 'activeHandChanged':
          this.hands = this.hands.map((h) => ({ ...h, isActive: h.id === event.handID }))
          this.changed()
          break

        case 'settled':
          this.credit(event.results)
          this.hands = this.hands.map((h) => ({ ...h, isActive: false, result: event.results.find((r) => r.handID === h.id) }))
          this.changed()
          await this.settleChips(event.results)
          break
      }
    }
    if (this.disposed) return
    this.actions = this.engine.availableActions()
    if (this.engine.phase === 'playerTurn') this.stage = 'playerTurn'
    else if (this.engine.phase === 'settled') this.stage = 'roundOver'
    this.changed()
  }

  /** Gewinne kommen vom Dealer, verlorene Einsätze gehen zum Dealer – ruhig, ohne Effektfeuerwerk. */
  private async settleChips(results: HandResult[]) {
    await this.wait(250)
    for (const result of results) {
      const key = this.betChipKeys.get(result.handID)
      if (key === undefined) continue
      const p = this.betPos(result.handID)
      if (result.outcome === 'win' || result.outcome === 'blackjack') {
        const payoutKey = entitySeq++
        this.chips = [...this.chips, { key: payoutKey, amount: result.payout - result.stake, x: p.x + 62, y: p.y, from: DEALER_TRAY }]
        this.changed()
        await this.wait(650)
        this.chips = this.chips.map((c) => (c.key === key || c.key === payoutKey ? { ...c, y: PLAYER_EDGE_Y + 40, gone: true } : c))
      } else if (result.outcome === 'push') {
        this.chips = this.chips.map((c) => (c.key === key ? { ...c, y: PLAYER_EDGE_Y + 40, gone: true } : c))
      } else {
        this.chips = this.chips.map((c) => (c.key === key ? { ...c, x: DEALER_TRAY.x, y: DEALER_TRAY.y, gone: true } : c))
      }
      this.changed()
      await this.wait(420)
    }
  }

  /** Bucht das Ergebnis genau einmal (auch wenn die Animation noch läuft oder abgebrochen wird). */
  private credit(results: readonly HandResult[]) {
    if (this.roundCredited) return
    this.roundCredited = true
    const stake = results.reduce((s, r) => s + r.stake, 0)
    const payout = results.reduce((s, r) => s + r.payout, 0)
    this.host.releaseFromTable(stake, payout)
    this.onRecord({
      stake,
      payout,
      handsWon: results.filter((r) => r.outcome === 'win' || r.outcome === 'blackjack').length,
      pushes: results.filter((r) => r.outcome === 'push').length,
      blackjacks: results.filter((r) => r.outcome === 'blackjack').length,
      hands: results.length,
    })
    const net = payout - stake
    const title = results.length === 1 ? handOutcomeTitle(results[0].outcome) : net > 0 ? 'GEWONNEN' : net < 0 ? 'VERLOREN' : 'PUSH'
    this.summary = { title, net }
  }
}

export interface BlackjackRoundRecord {
  stake: number
  payout: number
  handsWon: number
  pushes: number
  blackjacks: number
  hands: number
}

// ---------- Darstellung ----------

export function BlackjackTableView({ vm }: { vm: BlackjackViewModel }) {
  useObserve(vm)
  return (
    <TableStage width={STAGE_W} height={STAGE_H} padTop={70} focusWidth={880}>
      <Dealer x={STAGE_W / 2} y={PLANE_TOP + 40} width={300} reaching={vm.dealerReaching} />
      <TablePlane kind="bj" top={PLANE_TOP} height={PLANE_H} tilt={30} print={<BlackjackPrint />}>
        <Shoe x={SHOE.x} y={SHOE.y - 6} />
        <BetSpots vm={vm} />
        {vm.chips.map((c) => (
          <div key={c.key} style={{ opacity: c.gone ? 0 : 1, transition: 'opacity .45s ease .2s' }}>
            <TableChips amount={c.amount} x={c.x} y={c.y} from={c.from} width={60} />
          </div>
        ))}
        {vm.cards.map((c) => (
          <TableCard key={c.key} card={c.faceUp ? { rank: c.card.rank, suit: c.card.suit } : null}
            x={c.x} y={c.y} rotate={c.rotate} z={c.z} from={c.from}
            highlight={isActiveCard(vm, c.key)} />
        ))}
      </TablePlane>
    </TableStage>
  )
}

function isActiveCard(vm: BlackjackViewModel, key: number): boolean {
  if (vm.hands.length < 2) return false
  const active = vm.hands.find((h) => h.isActive)
  if (!active) return false
  return vm.playerCardKeys.get(active.id)?.includes(key) ?? false
}

function BetSpots({ vm }: { vm: BlackjackViewModel }) {
  const count = Math.max(1, vm.hands.length)
  const spacing = count >= 4 ? 228 : count === 3 ? 262 : 290
  const spots = Array.from({ length: count }, (_, i) => STAGE_W / 2 + (i - (count - 1) / 2) * spacing)
  return (
    <>
      {spots.map((x, i) => (
        <div class={`bet-spot ${vm.hands[i]?.isActive ? 'active' : ''}`}
          style={{ left: x - 46, top: BET_Y - 32, width: 92, height: 64, transition: 'left .35s ease' }} />
      ))}
    </>
  )
}

/** Aufdruck im Filz (wie bei echten Tischen, dezent). */
function BlackjackPrint() {
  return (
    <svg viewBox="0 0 948 436" width="100%" height="100%" preserveAspectRatio="none" style={{ position: 'absolute', inset: 0 }}>
      <defs>
        <path id="bj-arc-1" d="M150 150 Q474 262 798 150" />
        <path id="bj-arc-2" d="M200 178 Q474 282 748 178" />
      </defs>
      <text fill="rgba(240,228,196,.5)" font-size="25" font-weight="700" letter-spacing="5" font-family="Georgia, serif">
        <textPath href="#bj-arc-1" startOffset="50%" text-anchor="middle">BLACKJACK PAYS 3 TO 2</textPath>
      </text>
      <text fill="rgba(240,228,196,.36)" font-size="15" font-weight="600" letter-spacing="3" font-family="-apple-system, sans-serif">
        <textPath href="#bj-arc-2" startOffset="50%" text-anchor="middle">DEALER MUST STAND ON ALL 17s</textPath>
      </text>
      <path d="M150 150 Q474 262 798 150" fill="none" stroke="rgba(240,228,196,.18)" stroke-width="1.5" transform="translate(0 12)" />
    </svg>
  )
}

export function BlackjackControls({ vm, chips, onRescue }: { vm: BlackjackViewModel; chips: number; onRescue?: () => void }) {
  useObserve(vm)
  const narrow = useNarrow(980)
  if (vm.stage === 'betting') {
    const selector = (
      <ChipSelector values={BlackjackViewModel.chipValues} enabled={(v) => v <= chips - vm.pendingBet} onTap={(v) => vm.addChip(v)} />
    )
    const limits = <span style={{ fontSize: 12, color: 'var(--text-3)', whiteSpace: 'nowrap' }}>Min {vm.rules.minBet} · Max {ChipFormat.string(vm.rules.maxBet)}</span>
    const buttons = (
      <div style={{ display: 'flex', gap: 12 }}>
        <Button kind="ghost" size="large" label="Einsatz löschen" disabled={vm.pendingBet === 0} onClick={() => vm.clearBet()}><Icon name="close" /></Button>
        <Button kind="primary" size="large" disabled={vm.pendingBet < vm.rules.minBet} onClick={() => vm.deal()}>DEAL</Button>
      </div>
    )
    return (
      <div style={{ position: 'relative' }}>
        {chips < vm.rules.minBet && vm.pendingBet === 0 && onRescue && <RescueHint onClaim={onRescue} />}
        {narrow
          ? <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>{selector}<div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>{limits}{buttons}</div></div>
          : <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>{selector}<span style={{ flex: 1 }} />{limits}{buttons}</div>}
      </div>
    )
  }
  if (vm.stage === 'roundOver') {
    return (
      <div class="controls-row">
        <Button kind="secondary" size="large" onClick={() => vm.newRound()}>NEUE RUNDE</Button>
        <Button kind="primary" size="large" disabled={chips < vm.rules.minBet}
          onClick={async () => { vm.repeatLastBet(); await vm.deal() }}>
          {narrow ? 'GLEICHER EINSATZ' : `GLEICHER EINSATZ · ${ChipFormat.string(vm.lastBet)}`}
        </Button>
      </div>
    )
  }
  const enabled = vm.stage === 'playerTurn'
  const action = (title: string, icon: IconName, a: BlackjackAction, kind: 'primary' | 'secondary' | 'gold') => (
    <Button kind={kind} size="large" disabled={!(enabled && vm.actions.has(a) && vm.canAfford(a))} onClick={() => vm.perform(a)}>
      <Icon name={icon} size={18} stroke={2.6} /> {title}
    </Button>
  )
  return (
    <div class="controls-row">
      {action('HIT', 'plus', 'hit', 'primary')}
      {action('STAND', 'hand', 'stand', 'secondary')}
      {action('DOUBLE', 'double', 'double', 'gold')}
      {action('SPLIT', 'split', 'split', 'secondary')}
    </div>
  )
}

export function BlackjackInfo({ vm, chips }: { vm: BlackjackViewModel; chips: number }) {
  useObserve(vm)
  const stake = vm.stage === 'betting' ? vm.pendingBet : vm.hands.reduce((s, h) => s + h.bet, 0)
  const dealer = vm.dealerValueText
  return (
    <>
      <InfoItem title="Virtuelle Chips" value={ChipFormat.string(chips)} />
      <InfoItem title="Einsatz" value={ChipFormat.string(stake)} />
      {dealer && <InfoItem title="Dealer" value={dealer} />}
      {vm.hands.map((hand, index) => hand.cards.length > 0 && (
        <InfoItem title={vm.hands.length > 1 ? `Hand ${index + 1}` : 'Deine Hand'}
          value={hand.result ? handOutcomeTitle(hand.result.outcome) : HandValue.display(HandValue.of(hand.cards))}
          highlighted={hand.isActive}
          color={HandValue.of(hand.cards).total > 21 ? 'var(--red-bright)' : undefined} />
      ))}
      {vm.summary && vm.stage === 'roundOver' && <ResultPill title={vm.summary.title} net={vm.summary.net} />}
    </>
  )
}

/** Vollständiger Blackjack-Bildschirm. */
export function BlackjackScreen({ host, chips, onLeave, onRules, onHelp, onRecord, onRescue }: {
  host: GameHost
  chips: number
  onLeave: () => void
  onRules: () => void
  onHelp: () => void
  onRecord: (r: BlackjackRoundRecord) => void
  onRescue?: () => void
}) {
  const vm = useMemo(() => new BlackjackViewModel(host, onRecord), [])
  const [, setTick] = useState(0)
  useEffect(() => () => vm.leave(), [])
  useEffect(() => vm.subscribe(() => setTick((n) => n + 1)), [])
  return (
    <div class="screen" style={{ display: 'flex', flexDirection: 'column', background: '#000' }}>
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex' }}>
        <BlackjackTableView vm={vm} />
        <TopBar title="BLACKJACK" subtitle="1 Deck, jede Runde neu gemischt · Dealer steht auf 17 · Blackjack 3:2"
          onLeave={() => { vm.leave(); onLeave() }} onRules={onRules} onHelp={onHelp} />
      </div>
      <TableBar info={<BlackjackInfo vm={vm} chips={chips} />}>
        <BlackjackControls vm={vm} chips={chips} onRescue={onRescue} />
      </TableBar>
    </div>
  )
}
