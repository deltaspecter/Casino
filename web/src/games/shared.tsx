import { ChipIcon, Glass, Button } from '../ui/components'
import { Icon } from '../ui/icons'
import { ChipFormat } from '../ui/format'
import { denomination } from '../ui/table'

/** Auswahl der Chip-Werte für den Einsatz. */
export function ChipSelector({ values, enabled, onTap, size = 60 }: {
  values: number[]
  enabled: (value: number) => boolean
  onTap: (value: number) => void
  size?: number
}) {
  return (
    <div style={{ display: 'flex', gap: 12, flexWrap: 'nowrap' }}>
      {values.map((value) => {
        const d = denomination(value)
        const on = enabled(value)
        return (
          <button class="chip-btn" disabled={!on} aria-label={`Chip ${value}`} onClick={() => onTap(value)}
            style={{ opacity: on ? 1 : 0.35 }}>
            <ChipIcon color={d.base} size={size} label={ChipFormat.compact(value)} textColor={d.text} />
          </button>
        )
      })}
    </div>
  )
}

/** Hinweis, wenn der Kontostand nicht mehr für den Mindesteinsatz reicht. */
export function RescueHint({ onClaim, amount, canClaim = true }: { onClaim: () => void; amount?: number; canClaim?: boolean }) {
  return (
    <Glass radius={20} style={{ position: 'absolute', left: '50%', bottom: 'calc(100% + 18px)', transform: 'translateX(-50%)', padding: 12, display: 'flex', alignItems: 'center', gap: 12, whiteSpace: 'nowrap', zIndex: 10 }}>
      <Icon name="lifebuoy" color="var(--gold)" />
      <span style={{ fontSize: 14, fontWeight: 600 }}>
        {canClaim ? 'Zu wenig Chips? Hol dir ein kostenloses Startpaket.' : 'Tägliche Belohnung und Missionen bringen neue Chips.'}
      </span>
      {canClaim && <Button kind="gold" size="small" onClick={onClaim}>{amount ? `+${ChipFormat.string(amount)}` : 'Abholen'}</Button>}
    </Glass>
  )
}
