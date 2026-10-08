import { useEffect, useMemo, useRef, useState } from 'preact/hooks'
import { SlotCatalog, SlotMachine, SlotMath, type LineWin, type SlotMachineDefinition, type SpinResult } from '../core/slots'
import { Observable, sleep, useObserve } from '../app/observable'
import type { GameHost } from '../app/host'
import { AnimatedNumber, Glass, IconButton, NoCashValueNote, SectionTitle, Sheet, TopBar } from '../ui/components'
import { Icon } from '../ui/icons'
import { ChipFormat } from '../ui/format'
import { SlotSymbol, slotTheme, type SlotTheme } from './slotArt'
import { RescueHint } from './shared'

// ---------- Auszahlungsquoten (exakt berechnet) ----------

const reports = new Map<string, number>()

/** Berechnet die theoretischen Auszahlungsquoten einmalig (beim Laden). */
export function computeSlotReports(): void {
  for (const def of SlotCatalog.all) if (!reports.has(def.id)) reports.set(def.id, SlotMath.report(def).rtp)
}

export function rtpText(id: string): string {
  if (!reports.has(id)) computeSlotReports()
  const rtp = reports.get(id)
  return rtp === undefined ? '–' : (rtp * 100).toFixed(1).replace('.', ',') + ' %'
}

// ---------- View Model ----------

interface ReelColumn {
  /** Symbole von oben nach unten (inkl. je eines Puffersymbols oben und unten). */
  symbols: string[]
  /** Verschiebung in Zellen: 1 = Ruheposition (oberes Puffersymbol verdeckt). */
  offset: number
  /** Dauer der aktuellen Bewegung in ms (0 = sofort). */
  duration: number
  easing: string
  spinning: boolean
}

export interface SlotRecord { bet: number; payout: number }

export class SlotsViewModel extends Observable {
  readonly definition: SlotMachineDefinition
  readonly theme: SlotTheme
  private readonly machine: SlotMachine

  lineBetIndex = 1
  reels: ReelColumn[] = []
  isSpinning = false
  lastResult: SpinResult | null = null
  highlighted = new Set<string>()
  activeLine: LineWin | null = null
  displayedWin = 0
  /** Bereits gutgeschriebener, aber noch nicht angezeigter Gewinn (Walzen drehen noch). */
  pendingWin = 0
  celebration: { title: string; amount: number } | null = null

  private stops: number[]
  private cycleToken = 0
  private disposed = false

  constructor(machineID: string, private readonly host: GameHost, private readonly onRecord: (r: SlotRecord) => void) {
    super()
    this.definition = SlotCatalog.byID(machineID) ?? SlotCatalog.crimsonSevens
    this.machine = new SlotMachine(this.definition)
    this.theme = slotTheme(this.definition.id)
    // Startbild: zufällige Walzenpositionen (nur Optik, kein Spielergebnis)
    this.stops = this.definition.reelStrips.map((strip) => host.auxiliaryRandom.uniform(strip.length))
    this.reels = this.stops.map((stop, reel) => this.restColumn(reel, stop))
    this.lineBetIndex = Math.min(1, this.definition.lineBetOptions.length - 1)
  }

  private changed() { if (!this.disposed) this.emit() }

  private restColumn(reel: number, stop: number): ReelColumn {
    const strip = this.definition.reelStrips[reel]
    const n = strip.length
    const symbols: string[] = []
    for (let k = -1; k <= this.definition.rows; k++) symbols.push(strip[(((stop + k) % n) + n) % n])
    return { symbols, offset: 1, duration: 0, easing: 'linear', spinning: false }
  }

  get lineBet(): number { return this.definition.lineBetOptions[this.lineBetIndex] }
  get totalBet(): number { return this.lineBet * this.definition.paylines.length }

  changeBet(delta: number) {
    if (this.isSpinning) return
    const next = Math.min(Math.max(this.lineBetIndex + delta, 0), this.definition.lineBetOptions.length - 1)
    if (next === this.lineBetIndex) return
    this.lineBetIndex = next
    this.changed()
  }

  async spin() {
    if (this.isSpinning) return
    if (!this.host.debit(this.totalBet)) return

    this.isSpinning = true
    this.cycleToken++
    this.highlighted = new Set()
    this.activeLine = null
    this.displayedWin = 0
    this.celebration = null

    // RNG → Ergebnis: Die Stopppositionen werden hier, vor jeder Animation, gezogen
    // und sofort verbucht. Die Walzenanimation zeigt danach nur dieses feste Ergebnis.
    const result = this.machine.spin(this.lineBet, this.host.random)
    this.lastResult = result
    if (result.totalPayout > 0) {
      this.pendingWin = result.totalPayout
      this.host.credit(result.totalPayout)
    }
    this.onRecord({ bet: result.totalBet, payout: result.totalPayout })

    // Walzen-Spalten so aufbauen, dass sie physisch korrekt vom alten zum neuen Stopp laufen
    const rows = this.definition.rows
    this.reels = this.reels.map((_, i) => {
      const strip = this.definition.reelStrips[i]
      const n = strip.length
      const old = this.stops[i], next = result.stops[i]
      const distance = (((old - next) % n) + n) % n + (1 + Math.floor(i / 2)) * n
      const count = distance + rows
      const column = [strip[(((next - 1) % n) + n) % n]]
      for (let k = 0; k < count; k++) column.push(strip[(next + k) % n])
      column.push(strip[(old + rows) % n])
      return { symbols: column, offset: distance + 1, duration: 0, easing: 'linear', spinning: true }
    })
    this.stops = [...result.stops]
    this.changed()

    // Alle Walzen starten gemeinsam und stoppen nacheinander
    const reduced = this.host.reducedMotion
    const base = reduced ? 600 : 1100
    const step = reduced ? 150 : 320
    await sleep(40)
    this.reels = this.reels.map((r, i) => ({ ...r, offset: 0.86, duration: base + step * i, easing: 'cubic-bezier(.25,0,.2,1)' }))
    this.changed()
    let elapsed = 0
    for (let i = 0; i < this.reels.length; i++) {
      const duration = base + step * i
      await sleep(duration - elapsed)
      elapsed = duration
      this.reels = this.reels.map((r, k) => (k === i ? { ...r, offset: 1, duration: 260, easing: 'cubic-bezier(.3,1.6,.5,1)', spinning: false } : r))
      this.changed()
    }
    await sleep(280)
    // Ruhezustand: nur sichtbares Fenster + Puffer behalten
    this.reels = this.stops.map((stop, reel) => this.restColumn(reel, stop))
    this.isSpinning = false
    this.changed()
    await this.presentWin(result)
  }

  private async presentWin(result: SpinResult) {
    if (!result.isWin) {
      this.pendingWin = 0
      this.changed()
      return
    }
    const positions = new Set<string>()
    for (const w of result.lineWins) for (const p of w.positions) positions.add(`${p.reel}:${p.row}`)
    for (const p of result.scatterPositions) positions.add(`${p.reel}:${p.row}`)
    this.highlighted = positions
    if (result.winMultiplier >= 15) {
      this.celebration = { title: result.winMultiplier >= 50 ? 'MEGA WIN' : 'BIG WIN', amount: result.totalPayout }
    }
    // Gewinn hochzählen
    const steps = 20
    for (let k = 1; k <= steps; k++) {
      this.displayedWin = Math.floor((result.totalPayout * k) / steps)
      this.pendingWin = result.totalPayout - this.displayedWin
      this.changed()
      await sleep(30)
    }
    this.pendingWin = 0
    this.changed()

    // Gewinnlinien nacheinander hervorheben
    const wins = result.lineWins
    const token = this.cycleToken
    if (wins.length) {
      void (async () => {
        let index = 0
        while (token === this.cycleToken && !this.disposed) {
          this.activeLine = wins[index % wins.length]
          this.changed()
          index++
          await sleep(wins.length === 1 ? 3000 : 1300)
          if (wins.length === 1 && index > 1) break
        }
      })()
    }
    if (this.celebration) {
      await sleep(2600)
      if (token === this.cycleToken) {
        this.celebration = null
        this.changed()
      }
    }
  }

  stopEffects() {
    this.cycleToken++
    this.pendingWin = 0
    this.disposed = true
  }
}

// ---------- Darstellung ----------

function Reel({ reel, index, cell, highlighted }: { reel: ReelColumn; index: number; cell: number; highlighted: Set<string> }) {
  return (
    <div class="reel" style={{ width: cell, height: cell * 3 }}>
      <div class={`strip ${reel.spinning ? 'spinning' : ''}`} style={{
        transform: `translate3d(0, ${-reel.offset * cell}px, 0)`,
        transition: reel.duration ? `transform ${reel.duration}ms ${reel.easing}` : 'none',
      }}>
        {reel.symbols.map((symbol, i) => (
          <div style={{ width: cell, height: cell, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <SlotSymbol id={symbol} size={cell * 0.92}
              highlighted={!reel.spinning && reel.symbols.length === 5 && highlighted.has(`${index}:${i - 1}`)}
              dimmed={!reel.spinning && reel.symbols.length === 5 && highlighted.size > 0 && !highlighted.has(`${index}:${i - 1}`)} />
          </div>
        ))}
      </div>
    </div>
  )
}

function Cabinet({ vm }: { vm: SlotsViewModel }) {
  useObserve(vm)
  const host = useRef<HTMLDivElement>(null)
  const [cell, setCell] = useState(120)
  useEffect(() => {
    const el = host.current
    if (!el) return
    const update = () => setCell(Math.max(48, Math.min((el.clientWidth - 110) / 5, (el.clientHeight - 70) / 3, 170)))
    update()
    const ro = new ResizeObserver(update)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  const spacing = 10
  const gridW = cell * 5 + spacing * 4
  const gridH = cell * 3
  const t = vm.theme
  const line = vm.activeLine
  return (
    <div ref={host} style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div class="cabinet" style={{ '--glow': t.glow, '--accent': t.accent } as any}>
        <div style={{ position: 'relative', width: gridW, height: gridH, display: 'flex', gap: spacing }}>
          {vm.reels.map((reel, i) => <Reel reel={reel} index={i} cell={cell} highlighted={vm.highlighted} />)}
          {line && (
            <svg width={gridW} height={gridH} style={{ position: 'absolute', inset: 0, pointerEvents: 'none', overflow: 'visible' }}>
              <polyline fill="none" stroke={t.paylineColors[line.lineIndex % t.paylineColors.length]} stroke-width="5" stroke-linecap="round" stroke-linejoin="round"
                style={{ filter: `drop-shadow(0 0 6px ${t.paylineColors[line.lineIndex % t.paylineColors.length]})` }}
                points={vm.definition.paylines[line.lineIndex].map((row, reel) => `${reel * (cell + spacing) + cell / 2},${row * cell + cell / 2}`).join(' ')} />
            </svg>
          )}
        </div>
      </div>
    </div>
  )
}

function ControlBar({ vm, chips, onRescue, canClaimRescue }: { vm: SlotsViewModel; chips: number; onRescue: () => void; canClaimRescue: boolean }) {
  useObserve(vm)
  const disabled = vm.isSpinning || chips < vm.totalBet
  return (
    <Glass radius={34} class="slot-controls">
      {chips < vm.totalBet && !vm.isSpinning && <RescueHint onClaim={onRescue} canClaim={canClaimRescue} />}
      <div>
        <div class="label-caps">EINSATZ</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <button class="step-btn" disabled={vm.isSpinning} aria-label="Einsatz verringern" onClick={() => vm.changeBet(-1)}><Icon name="minus" stroke={3} /></button>
          <div style={{ minWidth: 104, textAlign: 'center' }}>
            <div class="numeric" style={{ fontSize: 26, fontWeight: 900 }}>{ChipFormat.string(vm.totalBet)}</div>
            <div style={{ fontSize: 11, color: 'var(--text-3)' }}>{vm.definition.paylines.length} Linien × {vm.lineBet}</div>
          </div>
          <button class="step-btn" disabled={vm.isSpinning} aria-label="Einsatz erhöhen" onClick={() => vm.changeBet(1)}><Icon name="plus" stroke={3} /></button>
        </div>
      </div>
      <span style={{ flex: 1 }} />
      <div style={{ textAlign: 'right', minWidth: 130 }}>
        <div class="label-caps">GEWINN</div>
        <div class={`numeric ${vm.displayedWin > 0 ? 'gold-text' : ''}`} style={{ fontSize: 30, fontWeight: 900, color: vm.displayedWin > 0 ? undefined : 'rgba(255,255,255,.4)' }}>
          {ChipFormat.string(vm.displayedWin)}
        </div>
      </div>
      <button class={`spin-btn ${vm.isSpinning ? 'busy' : ''}`} disabled={disabled} aria-label="Drehen" onClick={() => vm.spin()}>
        <Icon name={vm.isSpinning ? 'hourglass' : 'refresh'} size={36} stroke={3} />
      </button>
    </Glass>
  )
}

export function SlotMachineScreen({ machineID, host, chips, onLeave, onHelp, onRecord, onRescue, canClaimRescue }: {
  machineID: string
  host: GameHost
  chips: number
  onLeave: () => void
  onHelp: () => void
  onRecord: (r: SlotRecord) => void
  onRescue: () => void
  canClaimRescue: boolean
}) {
  const vm = useMemo(() => new SlotsViewModel(machineID, host, onRecord), [machineID])
  const [paytable, setPaytable] = useState(false)
  const [, setTick] = useState(0)
  useEffect(() => vm.subscribe(() => setTick((n) => n + 1)), [vm])
  useEffect(() => () => vm.stopEffects(), [vm])
  const t = vm.theme
  return (
    <div class="screen" style={{ background: `linear-gradient(180deg, ${t.background[0]}, ${t.background[1]})` }}>
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(circle at 50% 50%, ${t.glow}40, transparent 600px)`, pointerEvents: 'none' }} />
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', paddingTop: 'calc(84px + var(--safe-top))' }}>
        <Cabinet vm={vm} />
        <div style={{ padding: '0 calc(var(--gutter) + var(--safe-right)) calc(18px + var(--safe-bottom)) calc(var(--gutter) + var(--safe-left))' }}>
          <ControlBar vm={vm} chips={chips} onRescue={onRescue} canClaimRescue={canClaimRescue} />
        </div>
      </div>
      <TopBar title={vm.definition.name.toUpperCase()} subtitle={vm.definition.tagline} balance={chips - vm.pendingWin}
        onLeave={() => { vm.stopEffects(); onLeave() }} onRules={() => setPaytable(true)} onHelp={onHelp} />
      {vm.celebration && (
        <div class="celebration">
          <Glass radius={26} style={{ padding: '24px 40px', textAlign: 'center' }}>
            <div class="display gold-text" style={{ fontSize: 30, letterSpacing: 4 }}>{vm.celebration.title}</div>
            <div class="numeric" style={{ fontSize: 34, fontWeight: 900, marginTop: 8 }}>+<AnimatedNumber value={vm.celebration.amount} /></div>
          </Glass>
        </div>
      )}
      {paytable && <PaytableSheet definition={vm.definition} onClose={() => setPaytable(false)} />}
    </div>
  )
}

// ---------- Lobby ----------

export function SlotsLobby({ chips, onOpen, onLeave }: { chips: number; onOpen: (id: string) => void; onLeave: () => void }) {
  return (
    <div class="screen">
      <div class="light-sweep" />
      <div class="scroll">
        <div style={{ padding: 'calc(96px + var(--safe-top)) calc(var(--gutter) + var(--safe-right)) 40px calc(var(--gutter) + var(--safe-left))', display: 'flex', flexDirection: 'column', gap: 28 }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 22 }}>
            {SlotCatalog.all.map((machine) => {
              const t = slotTheme(machine.id)
              const preview = [...machine.symbols.filter((s) => s.kind === 'regular').slice(-3).map((s) => s.id), 'wild']
              return (
                <button class="machine-card" onClick={() => onOpen(machine.id)}
                  style={{ background: `linear-gradient(135deg, ${t.background[0]}, ${t.background[1]})`, borderColor: `${t.glow}80`, boxShadow: `0 10px 24px ${t.glow}4d` }}>
                  <div class="preview">{preview.map((id) => <SlotSymbol id={id} size={62} />)}</div>
                  <div class="display" style={{ fontSize: 22 }}>{machine.name.toUpperCase()}</div>
                  <div style={{ fontSize: 15, color: 'var(--text-2)', marginTop: 6 }}>{machine.tagline}</div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 16, fontSize: 13, fontWeight: 600, color: 'var(--text-3)' }}>
                    <span>5×3 · {machine.paylines.length} Linien</span>
                    <span>RTP {rtpText(machine.id)}</span>
                  </div>
                </button>
              )
            })}
          </div>
          <NoCashValueNote />
        </div>
      </div>
      <TopBar title="SLOTS" subtitle="Wähle deinen Automaten" balance={chips} onLeave={onLeave} />
    </div>
  )
}

// ---------- Regelwerk & Gewinntabelle ----------

function PaylineDiagram({ line, rows }: { line: readonly number[]; rows: number }) {
  return (
    <svg width="100" height="60" viewBox={`0 0 ${line.length * 20} ${rows * 20}`}>
      {line.map((row, c) => Array.from({ length: rows }, (_, r) => (
        <rect x={c * 20 + 1} y={r * 20 + 1} width="18" height="18" rx="3" fill={row === r ? 'var(--red)' : 'rgba(255,255,255,.08)'} />
      )))}
    </svg>
  )
}

export function PaytableSheet({ definition, onClose }: { definition: SlotMachineDefinition; onClose: () => void }) {
  const rule = (text: string) => (
    <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
      <span style={{ width: 7, height: 7, borderRadius: 9, background: 'var(--red)', marginTop: 8, flex: 'none' }} />
      <span style={{ fontSize: 16, color: 'var(--text-2)', lineHeight: 1.45 }}>{text}</span>
    </div>
  )
  return (
    <Sheet onClose={onClose}>
      <div class="stack" style={{ gap: 26 }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <h1 class="display" style={{ margin: 0, fontSize: 26, flex: 1 }}>RULES · {definition.name.toUpperCase()}</h1>
          <IconButton icon="close" size={40} label="Schließen" onClick={onClose} />
        </div>

        <SectionTitle title="Auszahlungen" subtitle="Vielfaches des Linieneinsatzes · Scatter: Vielfaches des Gesamteinsatzes" />
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: 14 }}>
          {[...definition.symbols].reverse().map((symbol) => (
            <div style={{ display: 'flex', gap: 14, alignItems: 'center', padding: 14, borderRadius: 18, background: 'var(--surface-raised)' }}>
              <SlotSymbol id={symbol.id} size={64} />
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 3 }}>
                {[5, 4, 3].map((n) => (
                  <div class="numeric" style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, fontSize: 15 }}>
                    <span style={{ color: 'var(--text-2)' }}>{n}×</span><span>{symbol.payout(n)}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        <SectionTitle title="Regeln" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {rule(`${definition.reelCount} Walzen × ${definition.rows} Reihen, ${definition.paylines.length} feste Gewinnlinien (alle immer aktiv).`)}
          {rule(`Gesamteinsatz = Linieneinsatz × ${definition.paylines.length}. Linieneinsätze: ${definition.lineBetOptions.join(', ')}.`)}
          {rule('Liniengewinne zählen von links nach rechts ab Walze 1, ab 3 gleichen Symbolen. Pro Linie wird nur der höchste Gewinn gezahlt.')}
          {rule('WILD ersetzt alle normalen Symbole, aber keinen SCATTER. Drei oder mehr WILD am Linienanfang zahlen selbst.')}
          {rule('SCATTER zahlt an jeder Position (Anzahl × Tabelle × Gesamteinsatz). Linien- und Scatter-Gewinne werden addiert.')}
          {rule('Es gibt keine Bonus-Symbole, Freispiele oder Jackpots.')}
        </div>

        <SectionTitle title="Gewinnlinien" />
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: 12 }}>
          {definition.paylines.map((line, i) => (
            <div style={{ padding: 10, borderRadius: 14, background: 'var(--surface-raised)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
              <PaylineDiagram line={line} rows={definition.rows} />
              <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-2)' }}>Linie {i + 1}</span>
            </div>
          ))}
        </div>

        <SectionTitle title="Zufall & Wahrscheinlichkeiten"
          subtitle="Jede Walze stoppt an einer gleichverteilt gezogenen Position ihres festen Streifens. Wahrscheinlichkeit eines Symbols an einer Position = Anzahl auf dem Streifen ÷ Streifenlänge." />
        <Glass radius={18} style={{ padding: 14, overflowX: 'auto' }}>
          <table class="prob-table">
            <thead>
              <tr><th style={{ textAlign: 'left' }}>Symbol</th>{definition.reelStrips.map((_, r) => <th>Walze {r + 1}</th>)}</tr>
            </thead>
            <tbody>
              {definition.symbols.map((symbol) => (
                <tr>
                  <td><SlotSymbol id={symbol.id} size={36} /></td>
                  {definition.reelStrips.map((strip, r) => (
                    <td>
                      <div class="numeric" style={{ fontWeight: 700, fontSize: 13 }}>{definition.count(symbol.id, r)}/{strip.length}</div>
                      <div style={{ fontSize: 11, color: 'var(--text-2)' }}>{(definition.probability(symbol.id, r) * 100).toFixed(1).replace('.', ',')} %</div>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </Glass>

        <SectionTitle title="Transparenz" />
        <div style={{ display: 'flex', gap: 16, alignItems: 'center', color: 'var(--text-2)', fontSize: 16, lineHeight: 1.45 }}>
          <Icon name="chart" size={28} color="var(--gold)" />
          <span>Theoretische Auszahlungsquote: <b style={{ color: '#fff' }}>{rtpText(definition.id)}</b> – exakt berechnet aus Walzenstreifen und Gewinntabelle. Es gibt keine Steuerung von Gewinnen oder Verlusten.</span>
        </div>
        <NoCashValueNote />
      </div>
    </Sheet>
  )
}
