import type { ComponentChildren, JSX } from 'preact'
import { useEffect, useRef, useState } from 'preact/hooks'
import { Icon, type IconName } from './icons'
import { ChipFormat } from './format'

// ---------- Buttons ----------

export type ButtonKind = 'primary' | 'secondary' | 'gold' | 'ghost'
export type ButtonSize = 'small' | 'medium' | 'large'

export function Button({ kind = 'primary', size = 'medium', full = false, disabled = false, onClick, children, label, style, class: cls }: {
  kind?: ButtonKind
  size?: ButtonSize
  full?: boolean
  disabled?: boolean
  onClick?: () => void
  children: ComponentChildren
  label?: string
  style?: JSX.CSSProperties
  class?: string
}) {
  return (
    <button
      class={`btn ${kind} ${size === 'medium' ? '' : size} ${full ? 'full' : ''} ${cls ?? ''}`}
      disabled={disabled}
      aria-label={label}
      style={style}
      onClick={() => {
        if (!disabled) onClick?.()
      }}
    >
      {children}
    </button>
  )
}

export function IconButton({ icon, size = 48, label, onClick }: {
  icon: IconName
  size?: number
  label: string
  onClick: () => void
}) {
  return (
    <button class="icon-btn" style={{ width: size, height: size }} aria-label={label} onClick={onClick}>
      <Icon name={icon} stroke={2.6} />
    </button>
  )
}

// ---------- Logo ----------

export function Logo({ size = 64, shimmer = true }: { size?: number; shimmer?: boolean }) {
  return (
    <div class={`logo ${shimmer ? 'shimmer' : ''}`} data-text="BLACK CASINO" style={{ fontSize: size }} aria-label="BlackCasino">
      <span class="black">BLACK</span>
      <span class="casino">CASINO</span>
    </div>
  )
}

// ---------- Chips ----------

export function ChipIcon({ color = 'var(--red)', size = 24, label, textColor = '#fff' }: {
  color?: string
  size?: number
  label?: string
  textColor?: string
}) {
  const dash = size * 0.2
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ flex: 'none', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,.45))' }} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={size / 2} fill={color} />
      <circle cx={size / 2} cy={size / 2} r={size / 2 - size * 0.12} fill="none" stroke="rgba(255,255,255,.92)"
        stroke-width={size * 0.16} stroke-dasharray={`${dash} ${dash}`} />
      <circle cx={size / 2} cy={size / 2} r={size * 0.24} fill={color} />
      <circle cx={size / 2} cy={size / 2} r={size * 0.24} fill="none" stroke="rgba(247,222,158,.8)" stroke-width={Math.max(1, size * 0.04)} />
      {label && (
        <text x={size / 2} y={size / 2 + size * 0.085} text-anchor="middle" font-size={size * 0.24} font-weight="900"
          font-family="ui-rounded, -apple-system, sans-serif" fill={textColor}>{label}</text>
      )}
    </svg>
  )
}

export function BalanceView({ amount, compact = false }: { amount: number; compact?: boolean }) {
  return (
    <div class="balance glass" style={compact ? { fontSize: 17, padding: '6px 14px 6px 6px' } : undefined}
      aria-label={`Kontostand ${ChipFormat.string(amount)} virtuelle Chips`}>
      <ChipIcon size={compact ? 20 : 26} />
      <AnimatedNumber value={amount} />
    </div>
  )
}

/** Zählt sanft zum neuen Wert hoch (rein optisch). */
export function AnimatedNumber({ value, format = ChipFormat.string }: { value: number; format?: (n: number) => string }) {
  const [shown, setShown] = useState(value)
  const from = useRef(value)
  useEffect(() => {
    const start = performance.now()
    const a = from.current
    const b = value
    if (a === b) return
    let frame = 0
    const tick = (t: number) => {
      const p = Math.min(1, (t - start) / 450)
      const eased = 1 - Math.pow(1 - p, 3)
      const v = Math.round(a + (b - a) * eased)
      setShown(v)
      from.current = v
      if (p < 1) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [value])
  return <span>{format(shown)}</span>
}

export function NoCashValueNote({ compact = false }: { compact?: boolean }) {
  return (
    <div class="note" style={compact ? { fontSize: 11 } : undefined}>
      {compact
        ? 'Virtuelle Chips · kein Echtgeldwert'
        : 'Reines Unterhaltungsspiel · Virtuelle Chips ohne realen Geldwert · Keine Käufe, keine Auszahlungen'}
    </div>
  )
}

export function ConnectionBadge({ online }: { online: boolean }) {
  return (
    <div class="badge glass" aria-label={online ? 'Online' : 'Offline'}>
      <span class="dot" style={{ background: online ? '#3ad16f' : '#c8c8c8', boxShadow: online ? '0 0 8px #3ad16f' : 'none' }} />
      {online ? 'Online' : 'Offline'}
    </div>
  )
}

// ---------- Sonstiges ----------

export function SectionTitle({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div>
      <div class="section-title">{title}</div>
      {subtitle && <div class="section-sub">{subtitle}</div>}
    </div>
  )
}

export function ProgressBar({ value, height = 8, gold = false }: { value: number; height?: number; gold?: boolean }) {
  const pct = Math.max(0, Math.min(1, value)) * 100
  return (
    <div class={`progress ${gold ? 'gold' : ''}`} style={{ height }}>
      <div style={{ width: `max(${height}px, ${pct}%)` }} />
    </div>
  )
}

export function Glass({ children, radius = 18, style, class: cls }: {
  children: ComponentChildren
  radius?: number
  style?: JSX.CSSProperties
  class?: string
}) {
  return <div class={`glass ${cls ?? ''}`} style={{ borderRadius: radius, ...style }}>{children}</div>
}

// ---------- Sheets & Dialoge ----------

export function Sheet({ onClose, children, medium = false, dismissable = true }: {
  onClose: () => void
  children: ComponentChildren
  medium?: boolean
  dismissable?: boolean
}) {
  return (
    <div class="sheet-backdrop" onClick={(e) => { if (dismissable && e.target === e.currentTarget) onClose() }}>
      <div class={`sheet ${medium ? 'medium' : ''}`} role="dialog" aria-modal="true">
        <div class="scroll">{children}</div>
      </div>
    </div>
  )
}

export function SheetHeader({ title, subtitle, onClose }: { title: string; subtitle?: string; onClose: () => void }) {
  return (
    <div class="sheet-header">
      <div style={{ flex: 1, minWidth: 0 }}>
        <h1 class="display">{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      <IconButton icon="close" size={44} label="Schließen" onClick={onClose} />
    </div>
  )
}

export function Dialog({ title, message, actions }: {
  title: string
  message: string
  actions: Array<{ label: string; kind?: ButtonKind; onClick: () => void }>
}) {
  return (
    <div class="dialog" role="alertdialog">
      <div>
        <h2>{title}</h2>
        <p>{message}</p>
        <div class="row">
          {actions.map((a) => (
            <Button kind={a.kind ?? 'secondary'} size="medium" onClick={a.onClick}>{a.label}</Button>
          ))}
        </div>
      </div>
    </div>
  )
}

export function RuleList({ items, numbered = false }: { items: string[]; numbered?: boolean }) {
  return (
    <Glass radius={20} style={{ padding: 18, display: 'flex', flexDirection: 'column', gap: 10 }}>
      {items.map((item, i) => (
        <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          {numbered
            ? <span class="numeric" style={{ color: 'var(--gold)', fontWeight: 800, width: 26, textAlign: 'right', flex: 'none' }}>{i + 1}.</span>
            : <span style={{ width: 7, height: 7, borderRadius: 9, background: 'var(--red)', marginTop: 8, flex: 'none' }} />}
          <span style={{ fontSize: 16, color: 'var(--text-2)', lineHeight: 1.45 }}>{item}</span>
        </div>
      ))}
    </Glass>
  )
}

export function InfoBlock({ icon, text }: { icon: IconName; text: string }) {
  return (
    <Glass radius={20} style={{ padding: 18, display: 'flex', gap: 16, alignItems: 'flex-start' }}>
      <span style={{ color: 'var(--gold)', flex: 'none' }}><Icon name={icon} size={24} /></span>
      <span style={{ fontSize: 15, color: 'var(--text-2)', lineHeight: 1.45 }}>{text}</span>
    </Glass>
  )
}

// ---------- Spiel-Kopfzeile & Tischleiste ----------

export function TopBar({ title, subtitle, balance, onLeave, onRules, onHelp, extra }: {
  title: string
  subtitle?: string
  balance?: number
  onLeave: () => void
  onRules?: () => void
  onHelp?: () => void
  extra?: ComponentChildren
}) {
  return (
    <div class="top-bar">
      <IconButton icon="back" label="Zurück" onClick={onLeave} />
      <div class="titles">
        <h1 class="display">{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {extra}
      {balance !== undefined && <BalanceView amount={balance} />}
      {onRules && (
        <Button kind="secondary" size="small" onClick={onRules}><Icon name="book" size={18} /> RULES</Button>
      )}
      {onHelp && <IconButton icon="help" label="Hilfe" onClick={onHelp} />}
    </div>
  )
}

export function TableBar({ info, children }: { info: ComponentChildren; children: ComponentChildren }) {
  return (
    <div class="table-bar">
      <div class="info-row">{info}</div>
      {children}
    </div>
  )
}

export function InfoItem({ title, value, highlighted = false, color }: {
  title: string
  value: string
  highlighted?: boolean
  color?: string
}) {
  return (
    <div class={`info-item ${highlighted ? 'hl' : ''}`}>
      <small>{title}</small>
      <div style={color ? { color } : undefined}>{value}</div>
    </div>
  )
}

export function ResultPill({ title, net }: { title: string; net: number }) {
  return (
    <div class={`result-pill ${net > 0 ? 'win' : ''}`}>
      <span>{title}</span>
      <span class={`numeric ${net > 0 ? 'pos' : net < 0 ? 'neg' : 'neu'}`}>{ChipFormat.signed(net)}</span>
    </div>
  )
}

/** Wählt zwischen einer breiten (einzeiligen) und einer schmalen Anordnung. */
export function useNarrow(breakpoint = 900): boolean {
  const [narrow, setNarrow] = useState(() => typeof window !== 'undefined' && window.innerWidth < breakpoint)
  useEffect(() => {
    const onResize = () => setNarrow(window.innerWidth < breakpoint)
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [breakpoint])
  return narrow
}
