/**
 * Realistische Spielkarten als SVG: weißer Kartenkörper, Serifen-Indizes in den Ecken,
 * klassische Pip-Anordnung (eine Herz-7 zeigt sieben Herzen) und gespiegelte Bildkarten.
 * Farbsymbole sind Vektorpfade – sie erscheinen nie als Emoji.
 */

export type SuitName = 'clubs' | 'diamonds' | 'hearts' | 'spades'

export const CARD_W = 384
export const CARD_H = 538
const RED = '#c70f1c'
const BLACK = '#121217'
const GOLD = '#bd9447'

const isRed = (s: SuitName) => s === 'hearts' || s === 'diamonds'
const colorFor = (s: SuitName) => (isRed(s) ? RED : BLACK)

export function rankLabel(rank: number): string {
  switch (rank) {
    case 11: return 'J'
    case 12: return 'Q'
    case 13: return 'K'
    case 14: return 'A'
    default: return String(rank)
  }
}

const f = (n: number) => Math.round(n * 100) / 100

/** SVG-Pfad eines Farbsymbols im Rechteck (Spitze oben). */
export function suitPath(suit: SuitName, x: number, y: number, w: number, h: number): string {
  const p = (px: number, py: number) => `${f(x + px * w)} ${f(y + py * h)}`
  const stem = `M${p(0.5, 0.58)} Q${p(0.47, 0.92)} ${p(0.28, 0.98)} L${p(0.72, 0.98)} Q${p(0.53, 0.92)} ${p(0.5, 0.58)}Z`
  switch (suit) {
    case 'hearts':
      return `M${p(0.5, 0.94)} C${p(0.3, 0.76)} ${p(0.04, 0.6)} ${p(0.04, 0.4)} C${p(0.04, 0.1)} ${p(0.4, 0.02)} ${p(0.5, 0.2)} C${p(0.6, 0.02)} ${p(0.96, 0.1)} ${p(0.96, 0.4)} C${p(0.96, 0.6)} ${p(0.7, 0.76)} ${p(0.5, 0.94)}Z`
    case 'diamonds':
      return `M${p(0.5, 0.02)} Q${p(0.7, 0.3)} ${p(0.9, 0.5)} Q${p(0.7, 0.7)} ${p(0.5, 0.98)} Q${p(0.3, 0.7)} ${p(0.1, 0.5)} Q${p(0.3, 0.3)} ${p(0.5, 0.02)}Z`
    case 'spades':
      return `M${p(0.5, 0.03)} C${p(0.7, 0.26)} ${p(0.95, 0.34)} ${p(0.95, 0.52)} C${p(0.95, 0.8)} ${p(0.62, 0.86)} ${p(0.5, 0.7)} C${p(0.38, 0.86)} ${p(0.05, 0.8)} ${p(0.05, 0.52)} C${p(0.05, 0.34)} ${p(0.3, 0.26)} ${p(0.5, 0.03)}Z ${stem}`
    case 'clubs': {
      const circle = (cx: number, cy: number, r: number) => {
        const X = x + cx * w, Y = y + cy * h
        return `M${f(X - r)} ${f(Y)} a${f(r)} ${f(r)} 0 1 0 ${f(2 * r)} 0 a${f(r)} ${f(r)} 0 1 0 ${f(-2 * r)} 0Z`
      }
      const r = w * 0.205
      return [circle(0.5, 0.26, r), circle(0.26, 0.56, r), circle(0.74, 0.56, r), circle(0.5, 0.5, w * 0.12), stem].join(' ')
    }
  }
}

/** Klassische Positionen im Pip-Feld (normiert; y > 0.5 wird um 180° gedreht gezeichnet). */
export function pipLayout(rank: number): Array<[number, number]> {
  const l = 0, c = 0.5, r = 1
  switch (rank) {
    case 2: return [[c, 0], [c, 1]]
    case 3: return [[c, 0], [c, 0.5], [c, 1]]
    case 4: return [[l, 0], [r, 0], [l, 1], [r, 1]]
    case 5: return [...pipLayout(4), [c, 0.5]]
    case 6: return [[l, 0], [r, 0], [l, 0.5], [r, 0.5], [l, 1], [r, 1]]
    case 7: return [...pipLayout(6), [c, 0.25]]
    case 8: return [...pipLayout(6), [c, 0.25], [c, 0.75]]
    case 9: return [...[0, 1 / 3, 2 / 3, 1].flatMap((y): Array<[number, number]> => [[l, y], [r, y]]), [c, 0.5]]
    case 10: return [...[0, 1 / 3, 2 / 3, 1].flatMap((y): Array<[number, number]> => [[l, y], [r, y]]), [c, 1 / 6], [c, 5 / 6]]
    case 14: return [[c, 0.5]]
    default: return []
  }
}

const SERIF = "Georgia, 'Times New Roman', serif"

function paper(): string {
  return `<defs>
<linearGradient id="pg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="#fefdfb"/><stop offset="1" stop-color="#f3f1ed"/></linearGradient>
</defs>
<rect x="0" y="0" width="${CARD_W}" height="${CARD_H}" rx="22" fill="url(#pg)"/>
<rect x="1" y="1" width="${CARD_W - 2}" height="${CARD_H - 2}" rx="21" fill="none" stroke="#bdbdbd" stroke-width="2"/>`
}

function corner(rank: number, suit: SuitName): string {
  const label = rankLabel(rank)
  const color = colorFor(suit)
  const size = label.length > 1 ? 52 : 60
  const spacing = label.length > 1 ? -4 : 0
  return `<text x="40" y="${14 + size * 0.86}" text-anchor="middle" font-family="${SERIF}" font-weight="bold" font-size="${size}" letter-spacing="${spacing}" fill="${color}">${label}</text>
<path d="${suitPath(suit, 23, 82, 34, 38)}" fill="${color}"/>`
}

function court(rank: number, suit: SuitName): string {
  const w = CARD_W, h = CARD_H
  const color = colorFor(suit)
  const fx = w * 0.19, fy = h * 0.12, fw = w * 0.62, fh = h * 0.76
  const midY = fy + fh / 2
  const cx = fx + fw / 2, cw = fw * 0.34, top = fy + 14
  const crown = rank === 11 ? '' :
    `<path d="M${f(cx - cw / 2)} ${f(top + 30)} L${f(cx - cw / 2)} ${f(top + 8)} L${f(cx - cw / 4)} ${f(top + 20)} L${f(cx)} ${f(top)} L${f(cx + cw / 4)} ${f(top + 20)} L${f(cx + cw / 2)} ${f(top + 8)} L${f(cx + cw / 2)} ${f(top + 30)}Z" fill="${GOLD}"/>`
  const half = `${crown}
<text x="${f(cx)}" y="${f(fy + fh * 0.08 + 18 + 104)}" text-anchor="middle" font-family="${SERIF}" font-weight="bold" font-size="118" fill="${color}">${rankLabel(rank)}</text>
<path d="${suitPath(suit, fx + 18, fy + 20, 40, 44)}" fill="${color}"/>`
  return `<clipPath id="cf"><rect x="${f(fx)}" y="${f(fy)}" width="${f(fw)}" height="${f(fh)}"/></clipPath>
<rect x="${f(fx)}" y="${f(fy)}" width="${f(fw)}" height="${f(fh)}" fill="#fbf7ee"/>
<g clip-path="url(#cf)" opacity="0.07" stroke="${color}" stroke-width="1.5">
${Array.from({ length: Math.ceil((fw + fh) / 9) }, (_, i) => {
  const x = fx - fh + i * 9
  return `<line x1="${f(x)}" y1="${f(fy + fh)}" x2="${f(x + fh)}" y2="${f(fy)}"/>`
}).join('')}
</g>
<rect x="${f(fx)}" y="${f(fy)}" width="${f(fw)}" height="${f(fh)}" fill="none" stroke="${color}" stroke-width="3"/>
<rect x="${f(fx + 6)}" y="${f(fy + 6)}" width="${f(fw - 12)}" height="${f(fh - 12)}" fill="none" stroke="${GOLD}" stroke-width="2"/>
<line x1="${f(fx + 6)}" y1="${f(midY)}" x2="${f(fx + fw - 6)}" y2="${f(midY)}" stroke="${color}" stroke-opacity="0.5" stroke-width="1.5"/>
${half}
<g transform="rotate(180 ${w / 2} ${h / 2})">${half}</g>`
}

function center(rank: number, suit: SuitName): string {
  const w = CARD_W, h = CARD_H
  const color = colorFor(suit)
  if (rank >= 11 && rank <= 13) return court(rank, suit)
  if (rank === 14) {
    const s = w * 0.4
    const x = (w - s) / 2, y = (h - s * 1.12) / 2
    let out = `<path d="${suitPath(suit, x, y, s, s * 1.12)}" fill="${color}"/>`
    if (suit === 'spades') {
      out += `<path d="${suitPath(suit, x + s * 0.16, y + s * 0.2, s * 0.68, s * 0.76)}" fill="none" stroke="#fff" stroke-opacity="0.9" stroke-width="2.5"/>`
    }
    return out
  }
  const ax = w * 0.27, ay = h * 0.17, aw = w * 0.46, ah = h * 0.66
  const pw = w * 0.165, ph = pw * 1.12
  return pipLayout(rank).map(([px, py]) => {
    const cx = ax + px * aw, cy = ay + py * ah
    const d = suitPath(suit, cx - pw / 2, cy - ph / 2, pw, ph)
    return py > 0.5
      ? `<path d="${d}" fill="${color}" transform="rotate(180 ${f(cx)} ${f(cy)})"/>`
      : `<path d="${d}" fill="${color}"/>`
  }).join('')
}

export function cardFaceSVG(rank: number, suit: SuitName): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CARD_W} ${CARD_H}" width="${CARD_W}" height="${CARD_H}">
${paper()}
${corner(rank, suit)}
<g transform="rotate(180 ${CARD_W / 2} ${CARD_H / 2})">${corner(rank, suit)}</g>
${center(rank, suit)}
</svg>`
}

export function cardBackSVG(): string {
  const ix = 20, iy = 20, iw = CARD_W - 40, ih = CARD_H - 40
  const lines: string[] = []
  for (let x = ix - ih; x < ix + iw + ih; x += 14) {
    lines.push(`<line x1="${x}" y1="${iy}" x2="${x + ih}" y2="${iy + ih}"/><line x1="${x + ih}" y1="${iy}" x2="${x}" y2="${iy + ih}"/>`)
  }
  const mx = CARD_W / 2, my = CARD_H / 2
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CARD_W} ${CARD_H}" width="${CARD_W}" height="${CARD_H}">
${paper()}
<clipPath id="bk"><rect x="${ix}" y="${iy}" width="${iw}" height="${ih}" rx="12"/></clipPath>
<rect x="${ix}" y="${iy}" width="${iw}" height="${ih}" rx="12" fill="#800d17"/>
<g clip-path="url(#bk)" stroke="#d94d52" stroke-opacity="0.55" stroke-width="1.4">${lines.join('')}</g>
<rect x="${ix + 8}" y="${iy + 8}" width="${iw - 16}" height="${ih - 16}" rx="8" fill="none" stroke="#fff" stroke-opacity="0.85" stroke-width="2"/>
<ellipse cx="${mx}" cy="${my}" rx="54" ry="70" fill="#800d17"/>
<ellipse cx="${mx}" cy="${my}" rx="49" ry="65" fill="none" stroke="#fff" stroke-opacity="0.85" stroke-width="2"/>
<text x="${mx}" y="${my + 15}" text-anchor="middle" font-family="${SERIF}" font-weight="bold" font-size="44" fill="#fff" fill-opacity="0.9">BC</text>
</svg>`
}

const cache = new Map<string, string>()

function toDataURL(svg: string): string {
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg.replace(/\n/g, ''))
}

/** Daten-URL der Kartenvorderseite (zwischengespeichert). */
export function cardFaceURL(rank: number, suit: SuitName): string {
  const key = `${rank}-${suit}`
  let url = cache.get(key)
  if (!url) {
    url = toDataURL(cardFaceSVG(rank, suit))
    cache.set(key, url)
  }
  return url
}

export function cardBackURL(): string {
  let url = cache.get('back')
  if (!url) {
    url = toDataURL(cardBackSVG())
    cache.set('back', url)
  }
  return url
}

/** Rendert alle Karten einmal vor, damit beim Austeilen nichts ruckelt. */
export async function preloadCards(): Promise<void> {
  const suits: SuitName[] = ['clubs', 'diamonds', 'hearts', 'spades']
  const urls = [cardBackURL()]
  for (const s of suits) for (let r = 2; r <= 14; r++) urls.push(cardFaceURL(r, s))
  if (typeof Image === 'undefined') return
  await Promise.all(urls.map((src) => new Promise<void>((resolve) => {
    const img = new Image()
    img.onload = () => {
      const anyImg = img as HTMLImageElement & { decode?: () => Promise<void> }
      if (anyImg.decode) anyImg.decode().then(() => resolve(), () => resolve())
      else resolve()
    }
    img.onerror = () => resolve()
    img.src = src
  })))
}
