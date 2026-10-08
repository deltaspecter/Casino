/** Hilfen rund um „Zum Home-Bildschirm“ (eigenständige App ohne Browserleisten). */

export function isStandalone(): boolean {
  if (typeof window === 'undefined') return false
  const nav = navigator as Navigator & { standalone?: boolean }
  return nav.standalone === true ||
    window.matchMedia?.('(display-mode: standalone)').matches ||
    window.matchMedia?.('(display-mode: fullscreen)').matches
}

export function isAppleTouchDevice(): boolean {
  if (typeof navigator === 'undefined') return false
  const ua = navigator.userAgent
  // iPadOS meldet sich als „Macintosh“, hat aber Touch.
  return /iPad|iPhone|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)
}

/** Öffentliche Adresse der App (zum Teilen mit Freunden). */
export function appURL(): string {
  const { origin, pathname } = window.location
  return origin + pathname.replace(/index\.html$/, '')
}

/** Teilen über das iPad-Teilen-Menü; sonst in die Zwischenablage. */
export async function shareApp(): Promise<'shared' | 'copied' | 'failed'> {
  const url = appURL()
  const text = 'Spiel mit mir BlackCasino – Blackjack, Poker & Slots mit virtuellen Chips. Link öffnen, dann „Teilen“ → „Zum Home-Bildschirm“.'
  try {
    if (navigator.share) {
      await navigator.share({ title: 'BlackCasino', text, url })
      return 'shared'
    }
  } catch (e) {
    if ((e as Error)?.name === 'AbortError') return 'failed'
  }
  try {
    await navigator.clipboard.writeText(url)
    return 'copied'
  } catch {
    return 'failed'
  }
}

/** Meldet den Service Worker an, damit die App offline startet. */
export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator) || import.meta.env.DEV) return
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').then((reg) => {
      // Neue Version gefunden: sofort aktivieren, beim nächsten Start ist sie da.
      reg.addEventListener('updatefound', () => {
        const worker = reg.installing
        worker?.addEventListener('statechange', () => {
          if (worker.state === 'installed' && navigator.serviceWorker.controller) worker.postMessage('skipWaiting')
        })
      })
    }).catch(() => { /* Offline-Start nicht verfügbar – App läuft trotzdem */ })
  })
}
