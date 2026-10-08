import { useEffect, useState } from 'preact/hooks'
import { ChipIcon, Logo, ProgressBar } from '../ui/components'
import { preloadCards } from '../ui/cardArt'

/**
 * Ladebildschirm mit echtem Fortschritt (Karten werden vorgerendert, Schrift geladen).
 * Keine künstliche Wartezeit: Sobald alles bereit ist, geht es weiter.
 */
export function LoadingScreen({ onFinished, steps }: {
  onFinished: () => void
  steps: Array<[string, () => Promise<unknown> | unknown]>
}) {
  const all: Array<[string, () => Promise<unknown> | unknown]> = [
    ['Karten werden gemischt', () => preloadCards()],
    ['Schrift wird geladen', () => (document as Document & { fonts?: FontFaceSet }).fonts?.ready],
    ...steps,
  ]
  const [progress, setProgress] = useState(0)
  const [status, setStatus] = useState(all[0][0])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      for (let i = 0; i < all.length; i++) {
        if (cancelled) return
        setStatus(all[i][0])
        try {
          await all[i][1]()
        } catch {
          // Ein fehlgeschlagener optischer Schritt blockiert den Start nicht.
        }
        setProgress((i + 1) / all.length)
      }
      if (!cancelled) onFinished()
    })()
    return () => { cancelled = true }
  }, [])

  return (
    <div class="screen loading">
      <div class="light-sweep" />
      <div class="ring-wrap">
        <div class="ring" />
        <div style={{ position: 'relative', filter: 'drop-shadow(0 0 30px rgba(219,18,41,.6))' }}>
          <ChipIcon size={120} />
          <span class="display gold-text" style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 30 }}>BC</span>
        </div>
      </div>
      <div style={{ position: 'relative', animation: 'rise 1s ease-out both .3s', maxWidth: '92vw' }}>
        <Logo size={Math.min(64, window.innerWidth / 9.5)} />
      </div>
      <div class="bottom">
        <div style={{ width: 'min(360px, 80vw)' }}><ProgressBar value={progress} height={4} gold /></div>
        <div class="status">{status}</div>
      </div>
    </div>
  )
}
