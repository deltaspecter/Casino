import { useState } from 'preact/hooks'
import { Button, Glass, Logo, NoCashValueNote } from '../ui/components'
import { Icon } from '../ui/icons'
import { ChipStack, Dealer, TableCard, TablePlane, TableStage } from '../ui/table'
import { isAppleTouchDevice, isStandalone } from '../ui/install'

/** Startbildschirm: dunkler Spieltisch mit Blackjack-Hand und Chips, darüber Logo und „SPIELEN“. */
export function StartScreen({ onPlay }: { onPlay: () => void }) {
  const [standalone] = useState(isStandalone)
  return (
    <div class="screen" style={{ background: '#000' }}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', animation: 'fade-in 1.4s ease-out both' }}>
        <TableStage width={1000} height={640}>
          <Dealer x={500} y={300} width={280} />
          <TablePlane kind="bj" top={250} height={390} tilt={32}>
            <TableCard card={{ rank: 14, suit: 'spades' }} x={470} y={170} rotate={-8} />
            <TableCard card={{ rank: 13, suit: 'hearts' }} x={520} y={175} rotate={6} z={1} />
            <div style={{ position: 'absolute', left: 640, top: 150 }}><ChipStack amount={6250} width={64} /></div>
            <div style={{ position: 'absolute', left: 720, top: 175 }}><ChipStack amount={1500} width={64} /></div>
            <div style={{ position: 'absolute', left: 300, top: 160 }}><ChipStack amount={525} width={64} /></div>
          </TablePlane>
        </TableStage>
      </div>
      <div class="start-overlay">
        <div style={{ maxWidth: '94vw' }}><Logo size={Math.min(84, window.innerWidth / 9)} /></div>
        <div class="tagline" style={{ fontSize: Math.min(20, window.innerWidth / 24) }}>PLAY&nbsp; •&nbsp; WIN&nbsp; •&nbsp; HAVE FUN</div>
        <div class="spacer" />
        <Button kind="primary" size="large" class="pulse" style={{ width: 280 }} onClick={onPlay}>SPIELEN</Button>
        {!standalone && isAppleTouchDevice() && (
          <Glass class="install-hint" radius={20} style={{ marginTop: 22 }}>
            <Icon name="download" size={26} color="var(--gold)" />
            <span>
              <b>Als App installieren:</b> Tippe in Safari auf <span class="share-glyph"><Icon name="share" size={18} /></span> „Teilen“
              und dann auf <b>„Zum Home-Bildschirm“</b>. BlackCasino startet danach wie eine App – im Vollbild und auch offline.
            </span>
          </Glass>
        )}
        <div style={{ marginTop: 18 }}><NoCashValueNote /></div>
      </div>
    </div>
  )
}
