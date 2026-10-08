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

// ---------- Dealer-Hände ----------

/** Position einer Dealer-Hand auf der Tischfläche (Fingerspitze des Mittelfingers). */
export interface HandPose {
  x: number
  y: number
  rotate?: number
}

const HAND_W = 140
/** Der Ärmel reicht weit nach oben aus dem Bild – er ist Teil der Grafik (kein Überlauf). */
const SLEEVE_TOP = -560
const HAND_H = 250 - SLEEVE_TOP
/** Fingerspitze des Mittelfingers in SVG-Koordinaten (gemessen ab Oberkante des Ärmels). */
const HAND_TIP = { x: 74, y: 226 - SLEEVE_TOP }

/**
 * Eine Hand des Dealers aus der Nahsicht: dunkler Ärmel, weiße Manschette, Handrücken nach oben.
 * Keine Figur und kein Gesicht – man sieht nur, was ein Spieler am Tisch tatsächlich sieht.
 * `mirrored` = linke Hand (Daumen zeigt dann ebenfalls zur Tischmitte).
 */
export function DealerHand({ pose, mirrored = false, width = 120, z = 60 }: { pose: HandPose; mirrored?: boolean; width?: number; z?: number }) {
  const s = width / HAND_W
  const ax = (mirrored ? HAND_W - HAND_TIP.x : HAND_TIP.x) * s
  const ay = HAND_TIP.y * s
  return (
    <div class="dealer-hand" style={{
      width, height: HAND_H * s,
      transformOrigin: `${ax}px ${ay}px`,
      transform: `translate3d(${pose.x - ax}px, ${pose.y - ay}px, ${z}px) rotate(${pose.rotate ?? 0}deg)`,
      zIndex: z,
    }}>
      <svg viewBox={`0 ${SLEEVE_TOP} ${HAND_W} ${HAND_H}`} width={width} height={HAND_H * s} style={{ display: 'block', overflow: 'visible', transform: mirrored ? 'scaleX(-1)' : undefined }} aria-hidden="true">
        <use href="#dealer-hand" />
      </svg>
    </div>
  )
}

/**
 * Pose, bei der die Fingerspitze auf `target` zeigt und der Arm zur Schulter (`base`) außerhalb des Bildes läuft.
 */
export function reachPose(target: { x: number; y: number }, base: { x: number; y: number }): HandPose {
  const angle = (Math.atan2(target.x - base.x, target.y - base.y) * 180) / Math.PI
  return { x: target.x, y: target.y, rotate: -angle }
}

/** Einmalige SVG-Definition der Hand (wird per <use> wiederverwendet). */
export function DealerHandDefs() {
  return (
    <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true">
      <defs>
        <radialGradient id="dh-back" cx=".45" cy=".45" r=".7">
          <stop offset="0" stop-color="#e2b89b" /><stop offset=".6" stop-color="#cf9d7e" /><stop offset="1" stop-color="#9c6b50" />
        </radialGradient>
        <linearGradient id="dh-finger" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stop-color="#9f6f54" /><stop offset=".4" stop-color="#dcb194" /><stop offset=".6" stop-color="#d6a98b" /><stop offset="1" stop-color="#996a50" />
        </linearGradient>
        <linearGradient id="dh-tip" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#000" stop-opacity="0" /><stop offset=".75" stop-color="#000" stop-opacity="0" /><stop offset="1" stop-color="#5a2e1c" stop-opacity=".25" />
        </linearGradient>
        <linearGradient id="dh-sleeve" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stop-color="#030304" /><stop offset=".5" stop-color="#26262c" /><stop offset="1" stop-color="#030304" />
        </linearGradient>
        <linearGradient id="dh-cuff" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stop-color="#a9a6a0" /><stop offset=".5" stop-color="#f7f6f2" /><stop offset="1" stop-color="#9e9b95" />
        </linearGradient>
        <filter id="dh-soft" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="6" /></filter>
        <filter id="dh-blur"><feGaussianBlur stdDeviation="1.2" /></filter>
        <g id="dealer-hand">
          <path class="dh-shadow" d="M44 100 C60 96 96 96 104 104 L118 160 C122 196 104 236 80 238 C58 240 40 226 38 192 Z" fill="#000" opacity=".5" filter="url(#dh-soft)" transform="translate(10 12)" />
          <path d="M20 -560 L120 -560 L106 74 L34 74 Z" fill="url(#dh-sleeve)" />
          <path d="M62 -560 L58 74" stroke="#000" stroke-opacity=".5" stroke-width="1" />
          <path d="M33 68 L107 68 L104 92 L36 92 Z" fill="url(#dh-cuff)" />
          <path d="M36 91 L104 91" stroke="#6f6c67" stroke-width="1.2" />
          <circle cx="93" cy="80" r="3.6" fill="#caa65e" stroke="#6e5427" stroke-width=".8" />
          <path d="M92 116 C104 120 114 132 118 148 C121 160 119 170 113 172 C107 174 103 168 101 160 C98 148 94 140 88 134 Z" fill="url(#dh-finger)" />
          <path d="M106 160 C107 167 115 168 116 162 C117 157 107 154 106 160 Z" fill="#e9c6b2" opacity=".7" />
          <path d="M46 156 C43 174 42 194 44 206 C45 214 55 215 57 207 C59 194 59 176 59 160 Z" fill="url(#dh-finger)" />
          <path d="M59 160 C58 182 58 206 60 220 C61 229 72 229 73 220 C75 204 74 182 73 162 Z" fill="url(#dh-finger)" />
          <path d="M73 162 C73 184 74 206 76 218 C77 226 88 226 89 217 C90 202 89 182 87 162 Z" fill="url(#dh-finger)" />
          <path d="M87 160 C88 176 89 192 91 201 C92 208 101 207 101 199 C102 186 100 172 98 158 Z" fill="url(#dh-finger)" />
          <g fill="url(#dh-tip)">
            <path d="M46 156 C43 174 42 194 44 206 C45 214 55 215 57 207 C59 194 59 176 59 160 Z" />
            <path d="M59 160 C58 182 58 206 60 220 C61 229 72 229 73 220 C75 204 74 182 73 162 Z" />
            <path d="M73 162 C73 184 74 206 76 218 C77 226 88 226 89 217 C90 202 89 182 87 162 Z" />
            <path d="M87 160 C88 176 89 192 91 201 C92 208 101 207 101 199 C102 186 100 172 98 158 Z" />
          </g>
          <path d="M42 90 C40 108 40 126 42 142 C43 152 45 160 50 166 C62 170 86 170 98 164 C102 154 102 140 100 124 C99 110 98 98 98 90 Z" fill="url(#dh-back)" />
          <g fill="#f1cfb8" opacity=".55" filter="url(#dh-blur)">
            <ellipse cx="52" cy="160" rx="5" ry="3.2" /><ellipse cx="66" cy="163" rx="5.5" ry="3.4" />
            <ellipse cx="80" cy="163" rx="5.5" ry="3.4" /><ellipse cx="93" cy="158" rx="4.6" ry="3" />
          </g>
          <g stroke="#7d5240" stroke-opacity=".32" stroke-width="1" fill="none" stroke-linecap="round">
            <path d="M47 182 Q51 180 56 182" /><path d="M61 188 Q66 186 71 188" /><path d="M76 186 Q81 184 86 186" /><path d="M89 180 Q93 178 98 180" />
          </g>
          <g fill="#e9c6b2" opacity=".75">
            <path d="M47 203 C47 210 55 210 55 203 C55 199 47 199 47 203 Z" />
            <path d="M62 216 C62 223 71 223 71 216 C71 211 62 211 62 216 Z" />
            <path d="M78 214 C78 220 87 220 87 214 C87 209 78 209 78 214 Z" />
            <path d="M92 197 C92 203 100 203 100 197 C100 193 92 193 92 197 Z" />
          </g>
          <g stroke="#f5dccb" stroke-opacity=".18" stroke-width="2.4" fill="none" stroke-linecap="round" filter="url(#dh-blur)">
            <path d="M62 104 Q57 132 53 156" /><path d="M69 104 Q67 134 66 158" /><path d="M76 104 Q78 134 80 158" /><path d="M83 106 Q88 132 92 154" />
          </g>
          <path d="M42 92 L98 92 L98 100 C80 104 60 104 42 100 Z" fill="#000" opacity=".25" filter="url(#dh-blur)" />
        </g>
      </defs>
    </svg>
  )
}

/** Kartenschlitten (Shoe) beim Dealer. */
export function Shoe({ x, y, width = 92 }: { x: number; y: number; width?: number }) {
  return <div class="shoe" style={{ left: x - width / 2, top: y - width * 0.35, width, height: width * 0.7, transform: 'rotate(-14deg)' }} />
}
