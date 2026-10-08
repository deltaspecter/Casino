import type { JSX } from 'preact'

/** Schlichte Linien-Icons (eigene Pfade, 24×24). */
const paths: Record<string, string> = {
  back: 'M15 5l-7 7 7 7',
  close: 'M6 6l12 12M18 6L6 18',
  help: 'M9.2 9a3 3 0 1 1 4.3 2.7c-.9.5-1.5 1.2-1.5 2.3v.5M12 18h.01',
  book: 'M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5zM4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5',
  gear: 'M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM19.4 13.5l1.8 1.4-2 3.4-2.1-.8a7 7 0 0 1-1.9 1.1L14.9 21h-3.8l-.3-2.4a7 7 0 0 1-1.9-1.1l-2.1.8-2-3.4 1.8-1.4a7 7 0 0 1 0-2.2L4.8 9.9l2-3.4 2.1.8a7 7 0 0 1 1.9-1.1L11.1 3h3.8l.3 2.4a7 7 0 0 1 1.9 1.1l2.1-.8 2 3.4-1.8 1.4a7 7 0 0 1 0 2.2z',
  gift: 'M3 9h18v4H3zM5 13h14v8H5zM12 9v12M12 9S10.5 4 7.5 4a2.5 2.5 0 0 0 0 5M12 9s1.5-5 4.5-5a2.5 2.5 0 0 1 0 5',
  flag: 'M5 21V4M5 4h11l-2 4 2 4H5',
  trophy: 'M8 4h8v5a4 4 0 0 1-8 0zM8 6H4.5a3 3 0 0 0 3.5 4M16 6h3.5a3 3 0 0 1-3.5 4M12 13v4M8 21h8M9 17h6v4H9z',
  chart: 'M4 20h16M7 16v-5M12 16V6M17 16v-8',
  users: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 6.5M18 14a6 6 0 0 1 3.5 6',
  shuffle: 'M3 7h3.5c2.5 0 4 1.5 5.5 5s3 5 5.5 5H21M3 17h3.5c1.4 0 2.5-.5 3.4-1.4M14 8.4c.9-.9 2-1.4 3.5-1.4H21M18 4l3 3-3 3M18 14l3 3-3 3',
  wifiOff: 'M3 3l18 18M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5-2.6M19 13a10 10 0 0 0-2.3-1.6M2 8.8a15 15 0 0 1 4.4-2.6M22 8.8A15 15 0 0 0 10.7 5M12 20h.01',
  wifi: 'M2 8.8a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16.1a5 5 0 0 1 7 0M12 20h.01',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  checkCircle: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM7.5 12.5l3 3 6-6.5',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  hand: 'M8 13V5.5a1.5 1.5 0 0 1 3 0V12M11 11V4a1.5 1.5 0 0 1 3 0v7M14 11V5.5a1.5 1.5 0 0 1 3 0V13M17 9.5a1.5 1.5 0 0 1 3 0V15a7 7 0 0 1-7 7h-1a7 7 0 0 1-5.6-2.8L3.6 15a1.5 1.5 0 0 1 2.3-2L8 15',
  double: 'M4 4h16v16H4zM12 16V8M8.5 11.5L12 8l3.5 3.5',
  split: 'M8 7l-5 5 5 5M16 7l5 5-5 5M3 12h18',
  info: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 11v6M12 7.5h.01',
  lifebuoy: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.9 4.9l4.3 4.3M14.8 14.8l4.3 4.3M14.8 9.2l4.3-4.3M4.9 19.1l4.3-4.3',
  dice: 'M4 4h16v16H4zM8.5 8.5h.01M15.5 8.5h.01M12 12h.01M8.5 15.5h.01M15.5 15.5h.01',
  lock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4',
  film: 'M4 3h16v18H4zM8 3v18M16 3v18M4 8h4M4 16h4M16 8h4M16 16h4M4 12h16',
  cpu: 'M7 7h10v10H7zM10 10h4v4h-4zM10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4',
  undo: 'M4 9h11a5 5 0 0 1 0 10H8M4 9l4-4M4 9l4 4',
  share: 'M12 15V3M7.5 7.5L12 3l4.5 4.5M5 12v8h14v-8',
  copy: 'M8 8h12v12H8zM16 8V4H4v12h4',
  play: 'M7 4l13 8-13 8z',
  star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z',
  sparkles: 'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8zM19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z',
  coins: 'M9 10c3.9 0 7-1.3 7-3s-3.1-3-7-3-7 1.3-7 3 3.1 3 7 3zM2 7v4c0 1.7 3.1 3 7 3s7-1.3 7-3V7M2 11v4c0 1.7 3.1 3 7 3 1 0 2-.1 2.8-.3M22 13c0 1.7-3.1 3-7 3s-7-1.3-7-3 3.1-3 7-3 7 1.3 7 3zM22 13v4c0 1.7-3.1 3-7 3s-7-1.3-7-3v-4',
  target: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',
  person: 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
  list: 'M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01',
  sliders: 'M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M16 4v4M10 10v4M18 16v4',
  grid: 'M4 4h16v16H4zM4 9.3h16M4 14.6h16M9.3 4v16M14.6 4v16',
  spade: 'M12 3s-8 6-8 10.5A4 4 0 0 0 11 16l-1.5 5h5L13 16a4 4 0 0 0 7-2.5C20 9 12 3 12 3z',
  crown: 'M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z',
  graduation: 'M2 9l10-5 10 5-10 5zM6 11v5c3 2.5 9 2.5 12 0v-5M22 9v6',
  flame: 'M12 22c4 0 7-2.7 7-7 0-5-5-7-5-12-3 2-6 6-6 9-1-1-1.5-2.5-1.5-3.5C4.5 10 5 13 5 15c0 4.3 3 7 7 7z',
  bolt: 'M13 2L4 14h7l-1 8 9-12h-7z',
  calendar: 'M4 5h16v16H4zM4 10h16M8 3v4M16 3v4',
  medal: 'M12 22a6 6 0 1 0 0-12 6 6 0 0 0 0 12zM8.5 11L5 3h5l2 4 2-4h5l-3.5 8',
  home: 'M3 11l9-8 9 8M5 9.5V21h14V9.5',
  download: 'M12 3v12M7.5 10.5L12 15l4.5-4.5M5 21h14',
  refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7',
  link: 'M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1',
  server: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
  trash: 'M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14',
  userPlus: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21a7 7 0 0 1 14 0M19 8v6M16 11h6',
  door: 'M5 21V3h11v18M16 21h3M12 12h.01M5 21h11',
  hourglass: 'M6 3h12M6 21h12M7 3v3a5 5 0 0 0 10 0V3M7 21v-3a5 5 0 0 1 10 0v3',
  robot: 'M5 9h14v10H5zM12 5v4M9 13h.01M15 13h.01M9 16.5h6M2 13v3M22 13v3M12 3.5h.01',
}

export type IconName = keyof typeof paths

export function Icon({ name, size = 24, stroke = 2, color = 'currentColor', fill = 'none', style }: {
  name: IconName
  size?: number | string
  stroke?: number
  color?: string
  fill?: string
  style?: JSX.CSSProperties
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={color} stroke-width={stroke}
      stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style={style}>
      <path d={paths[name]} />
    </svg>
  )
}
