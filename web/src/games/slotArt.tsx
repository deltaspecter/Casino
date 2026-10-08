/** Gestaltung der Automaten (Farben und Symbol-Darstellung). Die Spiellogik liegt in `core/slots`. */

export interface SlotTheme {
  accent: string
  glow: string
  background: [string, string]
  paylineColors: string[]
}

const LINE_COLORS = ['#f7de9e', '#ff3847', '#3fd8f2', '#3ad16f', '#ff9f2e', '#ff6fb5', '#ffe14d', '#7af0c8', '#b26bff', '#ffffff']

export function slotTheme(id: string): SlotTheme {
  switch (id) {
    case 'midnight-gems':
      return { accent: '#8c59ff', glow: '#6699ff', background: ['#0d0a24', '#03030a'], paylineColors: LINE_COLORS }
    case 'dragon-fortune':
      return { accent: '#ff8c1a', glow: '#d4ad66', background: ['#330a05', '#0d0300'], paylineColors: LINE_COLORS }
    default:
      return { accent: '#db1229', glow: '#ff3847', background: ['#2e030a', '#080002'], paylineColors: LINE_COLORS }
  }
}

type Glyph =
  | { kind: 'emoji'; value: string }
  | { kind: 'text'; value: string }
  | { kind: 'shape'; value: string }

interface SymbolArt {
  glyph: Glyph
  colors: string[]
  label?: string
}

const GOLD = ['#f7de9e', '#d4ad66', '#8c6b33']
const RED = ['#ff3847', '#db1229', '#6b0512']

export function symbolArt(id: string): SymbolArt {
  switch (id) {
    // Crimson Sevens
    case 'cherry': return { glyph: { kind: 'emoji', value: '🍒' }, colors: RED }
    case 'lemon': return { glyph: { kind: 'emoji', value: '🍋' }, colors: ['#ffe14d', '#ff9f2e'] }
    case 'plum': return { glyph: { kind: 'emoji', value: '🍇' }, colors: ['#b26bff', '#5b3cc4'] }
    case 'bell': return { glyph: { kind: 'shape', value: 'bell' }, colors: GOLD }
    case 'bar': return { glyph: { kind: 'text', value: 'BAR' }, colors: ['#ffffff', '#999999'] }
    case 'seven': return { glyph: { kind: 'text', value: '7' }, colors: RED }
    // Midnight Gems
    case 'topaz': return { glyph: { kind: 'shape', value: 'hexagon' }, colors: ['#ffe14d', '#ff9f2e'] }
    case 'amethyst': return { glyph: { kind: 'shape', value: 'octagon' }, colors: ['#cc80ff', '#8a2be2'] }
    case 'emerald': return { glyph: { kind: 'shape', value: 'shield' }, colors: ['#7af0c8', '#22b35b'] }
    case 'sapphire': return { glyph: { kind: 'shape', value: 'drop' }, colors: ['#3fd8f2', '#1f5bff'] }
    case 'ruby': return { glyph: { kind: 'shape', value: 'heart' }, colors: RED }
    case 'diamond': return { glyph: { kind: 'shape', value: 'diamond' }, colors: ['#ffffff', '#3fd8f2'] }
    // Dragon Fortune
    case 'coin': return { glyph: { kind: 'emoji', value: '🪙' }, colors: GOLD }
    case 'lantern': return { glyph: { kind: 'emoji', value: '🏮' }, colors: RED }
    case 'fan': return { glyph: { kind: 'emoji', value: '🎐' }, colors: ['#3fd8f2', '#1f5bff'] }
    case 'koi': return { glyph: { kind: 'emoji', value: '🎏' }, colors: RED }
    case 'tiger': return { glyph: { kind: 'emoji', value: '🐯' }, colors: ['#ff9f2e', '#ffe14d'] }
    case 'dragon': return { glyph: { kind: 'emoji', value: '🐉' }, colors: ['#3ad16f', '#7af0c8'] }
    // Gemeinsame Sondersymbole
    case 'wild': return { glyph: { kind: 'shape', value: 'crown' }, colors: GOLD, label: 'WILD' }
    case 'scatter': return { glyph: { kind: 'shape', value: 'sparkles' }, colors: ['#ffffff', '#f7de9e', '#d4ad66'], label: 'SCATTER' }
    default: return { glyph: { kind: 'text', value: '?' }, colors: ['#ffffff'] }
  }
}

const SHAPES: Record<string, string> = {
  bell: 'M50 12c-4 0-7 3-7 7v2c-14 4-21 16-21 30v16l-8 10h72l-8-10V51c0-14-7-26-21-30v-2c0-4-3-7-7-7zM40 82a10 10 0 0 0 20 0z',
  hexagon: 'M50 8l36 21v42L50 92 14 71V29z',
  octagon: 'M33 8h34l25 25v34L67 92H33L8 67V33z',
  shield: 'M50 8l36 12v26c0 24-16 40-36 46-20-6-36-22-36-46V20z',
  drop: 'M50 6C38 26 20 44 20 62a30 30 0 0 0 60 0C80 44 62 26 50 6z',
  heart: 'M50 88C22 68 8 52 8 34A20 20 0 0 1 50 24a20 20 0 0 1 42 10c0 18-14 34-42 54z',
  diamond: 'M28 12h44l20 24-42 52L8 36z',
  crown: 'M10 76l-4-46 24 20 20-34 20 34 24-20-4 46z',
  sparkles: 'M44 8l8 24 24 8-24 8-8 24-8-24-24-8 24-8zM76 56l4 12 12 4-12 4-4 12-4-12-12-4 12-4z',
}

let gradientSeq = 0

/** Darstellung eines einzelnen Symbols. */
export function SlotSymbol({ id, size, highlighted = false, dimmed = false }: {
  id: string
  size: number
  highlighted?: boolean
  dimmed?: boolean
}) {
  const art = symbolArt(id)
  const gid = `sg-${id}-${(gradientSeq = (gradientSeq + 1) % 1e6)}`
  const glyphSize = art.label ? 0.56 : 0.74
  return (
    <div class={`slot-symbol ${highlighted ? 'hl' : ''} ${dimmed ? 'dim' : ''}`}
      style={{ width: size, height: size, borderRadius: size * 0.18, '--sym-color': art.colors[0] } as any}>
      <svg viewBox={art.label ? '0 0 100 136' : '0 0 100 100'} width={size * glyphSize} height={size * glyphSize * (art.label ? 1.36 : 1)}
        style={{ overflow: 'visible' }} aria-label={id}>
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
            {art.colors.map((c, i) => <stop offset={art.colors.length === 1 ? 0 : i / (art.colors.length - 1)} stop-color={c} />)}
          </linearGradient>
        </defs>
        {art.glyph.kind === 'shape' && (
          <path d={SHAPES[art.glyph.value]} fill={`url(#${gid})`} style={{ filter: 'drop-shadow(0 3px 3px rgba(0,0,0,.5))' }} />
        )}
        {art.glyph.kind === 'text' && (
          <text x="50" y={art.glyph.value.length > 2 ? 64 : 84} text-anchor="middle" font-style="italic" font-weight="900"
            font-family="ui-rounded, -apple-system, 'Arial Black', sans-serif" font-size={art.glyph.value.length > 2 ? 40 : 92}
            fill={`url(#${gid})`} stroke="rgba(0,0,0,.35)" stroke-width="1.5" style={{ filter: 'drop-shadow(0 3px 3px rgba(0,0,0,.6))' }}>
            {art.glyph.value}
          </text>
        )}
        {art.glyph.kind === 'emoji' && (
          <text x="50" y="80" text-anchor="middle" font-size="76">{art.glyph.value}</text>
        )}
        {art.label && (
          <text x="50" y="128" text-anchor="middle" font-weight="900" font-size="22" letter-spacing="1" fill={`url(#${gid})`}
            font-family="-apple-system, sans-serif">{art.label}</text>
        )}
      </svg>
    </div>
  )
}
