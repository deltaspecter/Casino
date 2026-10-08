/** Zahlenformat wie in der iPad-App (deutsch, Tausenderpunkte). */
const formatter = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 })

export const ChipFormat = {
  string(value: number): string {
    return formatter.format(value)
  },
  signed(value: number): string {
    return (value > 0 ? '+' : value < 0 ? '−' : '±') + formatter.format(Math.abs(value))
  },
  /** Kompakt für Chips und kleine Labels (z. B. „12,5K“). */
  compact(value: number): string {
    if (value >= 1_000_000) return (value / 1_000_000).toFixed(1).replace('.', ',') + 'M'
    if (value >= 10_000) return Math.floor(value / 1_000) + 'K'
    if (value >= 1_000) return (value / 1_000).toFixed(1).replace('.', ',') + 'K'
    return String(value)
  },
  percent(part: number, total: number): string {
    if (total <= 0) return '–'
    return ((part / total) * 100).toFixed(1).replace('.', ',') + ' %'
  },
}

/** „in 5 Std. 12 Min.“ */
export function relativeTime(target: Date, now = new Date()): string {
  let s = Math.max(0, Math.round((target.getTime() - now.getTime()) / 1000))
  const h = Math.floor(s / 3600)
  s -= h * 3600
  const m = Math.ceil(s / 60)
  if (h > 0) return `in ${h} Std. ${m} Min.`
  return `in ${Math.max(1, m)} Min.`
}
