import type { ComponentChildren, JSX } from 'preact'
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'
import { cardBackURL, cardFaceURL, CARD_H, CARD_W, type SuitName } from './cardArt'

// ---------- Bühne mit fester logischer Größe ----------

/**
 * Skaliert einen Tisch mit fester logischer Größe passend in den verfügbaren Platz.
 * So wird auf keinem iPad (mini bis Pro 13", Hoch- und Querformat) eine Karte abgeschnitten.
 */
export function TableStage({ width, height, children, padTop = 0, focusWidth }: {
  width: number
  height: number
  children: ComponentChildren
  /** Breite, die mindestens sichtbar bleiben muss (Ränder der Rail dürfen im Hochformat abgeschnitten werden). */
  focusWidth?: number
  /** Platz für die Kopfzeile (in Bildschirmpunkten) */
  padTop?: number
}) {
  const host = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(0)
  const [offsetY, setOffsetY] = useState(0)

  useLayoutEffect(() => {
    const el = host.current
    if (!el) return
    const update = () => {
      const w = el.clientWidth
      const h = el.clientHeight - padTop
      const s = Math.min(w / (focusWidth ?? width), h / height)
      setScale(s)
      setOffsetY(padTop / 2)
    }
    update()
    const observer = new ResizeObserver(update)
    observer.observe(el)
    return () => observer.disconnect()
  }, [width, height, padTop, focusWidth])

  return (
    <div class="stage-host" ref={host}>
      <div class="stage" style={{
        width,
        height,
        transform: `translate(${-width * scale / 2}px, ${-height * scale / 2 + offsetY}px) scale(${scale})`,
        visibility: scale > 0 ? 'visible' : 'hidden',
      }}>
        {children}
      </div>
    </div>
  )
}

/** Tischfläche mit Perspektive. Inhalte werden in Tisch-Koordinaten (px der Fläche) platziert. */
export function TablePlane({ kind, top, height, tilt = 26, children, print }: {
  kind: 'bj' | 'pk'
  top: number
  height: number
  tilt?: number
  children?: ComponentChildren
  print?: ComponentChildren
}) {
  useFeltWeave()
  return (
    <div class={`plane-wrap ${kind}`} style={{ top, height }}>
      <div class="plane" style={{ transform: `rotateX(${tilt}deg)` }}>
        <div class="rail" />
        <div class="felt">{print && <div class="felt-print">{print}</div>}</div>
        {children}
      </div>
    </div>
  )
}

// ---------- Filzstruktur ----------

let weaveURL: string | null = null

/** Erzeugt einmalig eine kachelbare Stoffstruktur (feines Rauschen + Webmuster). */
function useFeltWeave() {
  useEffect(() => {
    if (weaveURL) return
    try {
      const size = 180
      const canvas = document.createElement('canvas')
      canvas.width = canvas.height = size
      const ctx = canvas.getContext('2d')
      if (!ctx) return
      const img = ctx.createImageData(size, size)
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          // Kosmetisches Rauschen (kein Spielzufall)
          const n = Math.random() * 26
          const weave = ((x + y) % 3 === 0 ? 10 : 0) + ((x - y + 300) % 4 === 0 ? 6 : 0)
          const v = 255 - n - weave
          const i = (y * size + x) * 4
          img.data[i] = v
          img.data[i + 1] = v
          img.data[i + 2] = v
          img.data[i + 3] = 255
        }
      }
      ctx.putImageData(img, 0, 0)
      weaveURL = canvas.toDataURL('image/png')
      document.documentElement.style.setProperty('--felt-weave', `url(${weaveURL})`)
    } catch {
      // Ohne Struktur weiterhin voll spielbar
    }
  }, [])
}

// ---------- Karten ----------

export const CARD_UNIT_W = 96
export const CARD_UNIT_H = Math.round(CARD_UNIT_W * CARD_H / CARD_W)

export interface CardFace {
  rank: number
  suit: SuitName
}

/**
 * Karte auf dem Tisch. Beim Erscheinen fliegt sie vom Schlitten (`from`) an ihren Platz,
 * dreht sich dabei leicht und landet; der Schatten folgt. Verdeckte Karten drehen sich beim Aufdecken um.
 */
export function TableCard({ card, x, y, rotate = 0, from, width = CARD_UNIT_W, highlight = false, dim = false, delay = 0, z = 0 }: {
  card: CardFace | null
  x: number
  y: number
  rotate?: number
  from?: { x: number; y: number }
  width?: number
  highlight?: boolean
  dim?: boolean
  delay?: number
  z?: number
}) {
  const height = width * CARD_H / CARD_W
  const [landed, setLanded] = useState(!from)
  // Zufällige, minimale Lageabweichung – rein kosmetisch, wie bei echten Karten.
  const jitter = useRef({ r: (Math.random() - 0.5) * 3, dx: (Math.random() - 0.5) * 3, dy: (Math.random() - 0.5) * 3 })
  useEffect(() => {
    if (landed) return
    let raf2 = 0
    const t = window.setTimeout(() => {
      raf2 = requestAnimationFrame(() => setLanded(true))
    }, 30 + delay)
    return () => {
      window.clearTimeout(t)
      cancelAnimationFrame(raf2)
    }
  }, [])

  const faceUp = card !== null
  // Im Flug liegt die Karte noch verdeckt; nach der Landung dreht sie sich um.
  const showFace = faceUp && landed
  const target = `translate3d(${x - width / 2 + jitter.current.dx}px, ${y - height / 2 + jitter.current.dy}px, ${z}px) rotate(${rotate + jitter.current.r}deg)`
  const start = from ? `translate3d(${from.x - width / 2}px, ${from.y - height / 2}px, ${z + 40}px) rotate(${rotate - 70}deg) scale(0.92)` : target
  const style: JSX.CSSProperties = {
    width,
    height,
    transform: landed ? target : start,
    zIndex: z + 1,
  }
  return (
    <div class={`tcard ${landed ? '' : 'flying'} ${highlight ? 'highlight' : ''} ${dim ? 'dim' : ''}`} style={style}>
      <div class="shadow" />
      <div class={`inner ${showFace ? '' : 'back'}`} style={{ transitionDelay: showFace ? '0.32s' : '0s' }}>
        <div class="face">{card && <img src={cardFaceURL(card.rank, card.suit)} alt="" draggable={false} />}</div>
        <div class="backside"><img src={cardBackURL()} alt="" draggable={false} /></div>
      </div>
    </div>
  )
}

/** Flache Karte für Menüs und Übersichten. */
export function FlatCard({ card, width = 70, rotate = 0, style }: {
  card: CardFace | null
  width?: number
  rotate?: number
  style?: JSX.CSSProperties
}) {
  return (
    <img
      src={card ? cardFaceURL(card.rank, card.suit) : cardBackURL()}
      alt={card ? 'Karte' : 'verdeckte Karte'}
      draggable={false}
      style={{
        width,
        height: width * CARD_H / CARD_W,
        borderRadius: width * 0.06,
        transform: `rotate(${rotate}deg)`,
        boxShadow: `0 1px 1px rgba(0,0,0,.35), ${width * 0.02}px ${width * 0.06}px ${width * 0.12}px rgba(0,0,0,.4)`,
        ...style,
      }}
    />
  )
}

// ---------- Chips ----------

export interface Denomination {
  value: number
  base: string
  stripe: string
  text: string
  label: string
}

export const DENOMINATIONS: Denomination[] = [
  { value: 1, base: '#ebebeb', stripe: '#db1229', text: '#141414', label: '1' },
  { value: 5, base: '#cc0f21', stripe: '#f5f5f5', text: '#fff', label: '5' },
  { value: 25, base: '#147340', stripe: '#f5f5f5', text: '#fff', label: '25' },
  { value: 100, base: '#151517', stripe: '#f5f5f5', text: '#fff', label: '100' },
  { value: 500, base: '#61238c', stripe: '#f5f5f5', text: '#fff', label: '500' },
  { value: 1000, base: '#d9ad4d', stripe: '#1a1a1a', text: '#141414', label: '1K' },
  { value: 5000, base: '#730514', stripe: '#f7de9e', text: '#fff', label: '5K' },
]

export function denomination(value: number): Denomination {
  return DENOMINATIONS.find((d) => d.value === value) ?? DENOMINATIONS[3]
}

/** Zerlegt einen Betrag in Chips (größte zuerst), begrenzt für die Darstellung. */
export function breakdown(amount: number, maxChips = 24): Denomination[] {
  let rest = amount
  const out: Denomination[] = []
  for (const d of [...DENOMINATIONS].reverse()) {
    while (rest >= d.value && out.length < maxChips) {
      out.push(d)
      rest -= d.value
    }
  }
  return out
}

/** Chip-Stapel mit sichtbaren Seitenflächen, Randeinlagen und Schatten. */
export function ChipStack({ amount, width = 56, maxChips = 12 }: { amount: number; width?: number; maxChips?: number }) {
  const chips = breakdown(amount, maxChips).reverse() // größte unten
  const w = width
  const h = w * 0.42
  const t = w * 0.1
  const height = h + t * chips.length + 8
  const cx = w / 2 + 3
  return (
    <svg width={w + 8} height={height} viewBox={`0 0 ${w + 8} ${height}`} style={{ overflow: 'visible', display: 'block' }} aria-label={`Chips ${amount}`}>
      <ellipse cx={cx + 2} cy={height - h / 2 - 2 + 3} rx={w / 2 + 2} ry={h / 2 + 1} fill="rgba(0,0,0,.45)" style={{ filter: 'blur(2.5px)' }} />
      {chips.map((d, i) => {
        const base = height - h / 2 - 4 - i * t
        const topY = base - t
        const stripes = [0.14, 0.38, 0.62, 0.86]
        return (
          <g key={i}>
            {/* Seitenfläche */}
            <path d={`M${cx - w / 2} ${topY} L${cx - w / 2} ${base} A${w / 2} ${h / 2} 0 0 0 ${cx + w / 2} ${base} L${cx + w / 2} ${topY} Z`} fill={d.base} />
            <path d={`M${cx - w / 2} ${topY} L${cx - w / 2} ${base} A${w / 2} ${h / 2} 0 0 0 ${cx + w / 2} ${base} L${cx + w / 2} ${topY} Z`} fill="url(#chip-side-shade)" />
            {stripes.map((s) => {
              const sx = cx - w / 2 + s * w
              const curve = Math.sqrt(Math.max(0, 1 - Math.pow((sx - cx) / (w / 2), 2))) * h / 2
              return <rect x={sx - w * 0.035} y={topY + curve} width={w * 0.07} height={t} fill={d.stripe} opacity={0.92} />
            })}
            {/* Oberseite */}
            <ellipse cx={cx} cy={topY} rx={w / 2} ry={h / 2} fill={d.base} />
            <ellipse cx={cx} cy={topY} rx={w / 2 * 0.86} ry={h / 2 * 0.86} fill="none" stroke={d.stripe} stroke-width={w * 0.07}
              stroke-dasharray={`${w * 0.12} ${w * 0.1}`} opacity={0.9} />
            <ellipse cx={cx} cy={topY} rx={w / 2 * 0.56} ry={h / 2 * 0.56} fill={d.base} stroke="rgba(247,222,158,.55)" stroke-width={0.8} />
            <ellipse cx={cx} cy={topY} rx={w / 2} ry={h / 2} fill="url(#chip-top-light)" />
          </g>
        )
      })}
      <defs>
        <linearGradient id="chip-side-shade" x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stop-color="#000" stop-opacity=".45" />
          <stop offset=".35" stop-color="#000" stop-opacity=".05" />
          <stop offset=".7" stop-color="#000" stop-opacity=".15" />
          <stop offset="1" stop-color="#000" stop-opacity=".55" />
        </linearGradient>
        <radialGradient id="chip-top-light" cx=".35" cy=".3" r=".8">
          <stop offset="0" stop-color="#fff" stop-opacity=".22" />
          <stop offset="1" stop-color="#000" stop-opacity=".12" />
        </radialGradient>
      </defs>
    </svg>
  )
}

/** Chip-Stapel auf dem Tisch; gleitet von `from` an seinen Platz (z. B. vom Spieler ins Einsatzfeld). */
export function TableChips({ amount, x, y, from, width = 56, z = 0 }: {
  amount: number
  x: number
  y: number
  from?: { x: number; y: number }
  width?: number
  z?: number
}) {
  const [placed, setPlaced] = useState(!from)
  useEffect(() => {
    if (placed) return
    const raf = requestAnimationFrame(() => requestAnimationFrame(() => setPlaced(true)))
    return () => cancelAnimationFrame(raf)
  }, [])
  const chips = Math.min(12, breakdown(amount, 12).length)
  const h = width * 0.42 + width * 0.1 * chips + 8
  const pos = placed || !from ? { x, y } : from
  if (amount <= 0) return null
  return (
    <div class="tchips" style={{
      transform: `translate3d(${pos.x - (width + 8) / 2}px, ${pos.y - h + width * 0.21 + 4}px, ${z}px)`,
      opacity: placed ? 1 : 0.6,
      zIndex: 2 + z,
    }}>
      <ChipStack amount={amount} width={width} />
    </div>
  )
}

// ---------- Dealer ----------

/**
 * Gesichtslose, realistisch proportionierte Dealer-Figur (Weste, Hemd, dunkelrote Krawatte).
 * Bewusst ohne Gesichtszüge – keine Nachbildung einer realen Person.
 */
export function Dealer({ x, y, width = 300, reaching = false }: { x: number; y: number; width?: number; reaching?: boolean }) {
  const h = width * 0.9
  return (
    <div class={`dealer ${reaching ? 'reach' : ''}`} style={{ left: x - width / 2, top: y - h, width, height: h }}>
      <svg viewBox="0 0 300 270" width={width} height={h} style={{ overflow: 'visible' }}>
        <defs>
          <radialGradient id="dl-skin" cx=".42" cy=".35" r=".75">
            <stop offset="0" stop-color="#c9b2a0" />
            <stop offset=".6" stop-color="#9c8372" />
            <stop offset="1" stop-color="#5e4b40" />
          </radialGradient>
          <linearGradient id="dl-hair" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#2a2420" />
            <stop offset="1" stop-color="#15110f" />
          </linearGradient>
          <linearGradient id="dl-shirt" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="#9d9a95" />
            <stop offset=".45" stop-color="#ecebe7" />
            <stop offset="1" stop-color="#8f8c87" />
          </linearGradient>
          <linearGradient id="dl-vest" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="#050506" />
            <stop offset=".4" stop-color="#1d1d22" />
            <stop offset=".6" stop-color="#1a1a1f" />
            <stop offset="1" stop-color="#040405" />
          </linearGradient>
          <linearGradient id="dl-tie" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="#3d0610" />
            <stop offset=".5" stop-color="#7a0f1d" />
            <stop offset="1" stop-color="#3d0610" />
          </linearGradient>
          <linearGradient id="dl-sleeve" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#d9d7d2" />
            <stop offset="1" stop-color="#8c8984" />
          </linearGradient>
          <radialGradient id="dl-key" cx=".5" cy=".2" r=".9">
            <stop offset="0" stop-color="#ffd9a8" stop-opacity=".18" />
            <stop offset="1" stop-color="#000" stop-opacity="0" />
          </radialGradient>
        </defs>
        <g class="body">
          {/* Schultern & Oberkörper */}
          <path d="M40 270 C40 205 58 168 104 150 L196 150 C242 168 260 205 260 270 Z" fill="url(#dl-shirt)" />
          {/* Weste */}
          <path d="M66 270 C66 214 78 180 112 160 L138 166 L150 230 L162 166 L188 160 C222 180 234 214 234 270 Z" fill="url(#dl-vest)" />
          <path d="M150 230 L150 270" stroke="#000" stroke-opacity=".5" stroke-width="1.5" />
          <circle cx="150" cy="242" r="2.4" fill="#8c7a55" />
          <circle cx="150" cy="258" r="2.4" fill="#8c7a55" />
          {/* Kragen & Krawatte */}
          <path d="M126 146 L150 168 L174 146 L168 138 L150 150 L132 138 Z" fill="#f2f1ed" />
          <path d="M144 158 L156 158 L159 168 L153 222 L150 228 L147 222 L141 168 Z" fill="url(#dl-tie)" />
          <path d="M144 158 L156 158 L154 166 L146 166 Z" fill="#5a0a15" />
          {/* Hals */}
          <path d="M132 118 L168 118 L170 146 L150 152 L130 146 Z" fill="url(#dl-skin)" />
          <path d="M132 136 C142 146 158 146 168 136 L168 146 L150 152 L132 146 Z" fill="#000" opacity=".22" />
          {/* Linker Arm (ruhend) */}
          <path d="M58 190 C44 214 46 246 62 268 L92 268 C84 240 84 214 92 196 Z" fill="url(#dl-sleeve)" />
          {/* Rechter Arm (greift zum Schlitten) */}
          <g class="arm-r">
            <path d="M242 190 C256 214 254 246 238 268 L208 268 C216 240 216 214 208 196 Z" fill="url(#dl-sleeve)" />
          </g>
          {/* Kopf (gesichtslos, wie eine Schaufensterfigur) */}
          <g class="head">
            <ellipse cx="150" cy="82" rx="37" ry="46" fill="url(#dl-skin)" />
            <ellipse cx="113" cy="86" rx="6" ry="11" fill="#8a7263" />
            <ellipse cx="187" cy="86" rx="6" ry="11" fill="#8a7263" />
            <path d="M112 78 C110 44 128 32 150 32 C174 32 192 44 188 78 C184 62 172 54 150 54 C128 54 116 62 112 78 Z" fill="url(#dl-hair)" />
            <ellipse cx="139" cy="70" rx="12" ry="16" fill="#fff" opacity=".06" />
          </g>
        </g>
      </svg>
    </div>
  )
}

/** Kartenschlitten neben dem Dealer. */
export function Shoe({ x, y, width = 92 }: { x: number; y: number; width?: number }) {
  return <div class="shoe" style={{ left: x - width / 2, top: y - width * 0.35, width, height: width * 0.7, transform: 'rotate(-14deg)' }} />
}
