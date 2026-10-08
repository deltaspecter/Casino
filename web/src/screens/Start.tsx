import { useState } from 'preact/hooks'
import { Button, Glass, Logo, NoCashValueNote } from '../ui/components'
import { Icon } from '../ui/icons'
import { ChipStack, DealerHand, TableCard, TablePlane, TableStage, reachPose } from '../ui/table'
import { isAppleTouchDevice, isStandalone } from '../ui/install'

/** Startbildschirm: dunkler Spieltisch mit Blackjack-Hand und Chips, darüber Logo und „SPIELEN“. */
export function StartScreen({ onPlay }: { onPlay: () => void }) {
  const [standalone] = useState(isStandalone)
  return (
    <div class="screen" style={{ background: '#000' }}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', animation: 'fade-in 1.4s ease-out both' }}>
        <TableStage width={1000} height={640}>
          <TablePlane kind="bj" top={-180} height={820} tilt={34}>
            <TableCard card={{ rank: 14, suit: 'spades' }} x={470} y={470} rotate={-8} />
            <TableCard card={{ rank: 13, suit: 'hearts' }} x={520} y={476} rotate={6} z={1} />
            <div style={{ position: 'absolute', left: 640, top: 430 }}><ChipStack amount={6250} width={66} /></div>
            <div style={{ position: 'absolute', left: 724, top: 462 }}><ChipStack amount={1500} width={66} /></div>
            <div style={{ position: 'absolute', left: 290, top: 452 }}><ChipStack amount={525} width={66} /></div>
            <DealerHand pose={reachPose({ x: 404, y: 300 }, { x: 300, y: -260 })} />
            <DealerHand pose={reachPose({ x: 610, y: 290 }, { x: 700, y: -260 })} mirrored />
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
