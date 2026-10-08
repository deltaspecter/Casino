import type { AppModel } from '../app/model'
import { useObserve } from '../app/observable'
import { RewardTable } from '../core/progression'
import { BalanceView, ConnectionBadge, IconButton, Logo, NoCashValueNote, Dialog, Glass } from '../ui/components'
import { Icon, type IconName } from '../ui/icons'
import { ChipFormat } from '../ui/format'
import { FlatCard, ChipStack } from '../ui/table'
import { SlotSymbol } from '../games/slotArt'
import { isStandalone, shareApp } from '../ui/install'
import { useState } from 'preact/hooks'

export function MainMenu({ model, online }: { model: AppModel; online: boolean }) {
  useObserve(model)
  const [offlineAlert, setOfflineAlert] = useState(false)
  const p = model.profile
  const missionsReady = p.dailyMissions.filter((m) => p.isMissionComplete(m) && !m.isClaimed).length
  const missionsClaimed = p.dailyMissions.filter((m) => m.isClaimed).length
  const achievementsReady = [...p.unlockedAchievements].filter((id) => !p.claimedAchievements.has(id)).length

  const openMultiplayer = (name: 'friends' | 'randomMatch') => {
    if (online) model.navigate({ name })
    else setOfflineAlert(true)
  }

  const invite = async () => {
    const result = await shareApp()
    if (result === 'copied') model.show({ icon: 'link', title: 'Link kopiert', subtitle: 'Schick ihn deinen Freunden – sie öffnen ihn in Safari.' })
  }

  return (
    <div class="screen">
      <div class="light-sweep" />
      <div class="scroll">
        <div class="menu">
          <div class="menu-header">
            <Logo size={Math.min(30, window.innerWidth / 16)} />
            <span class="grow" />
            <ConnectionBadge online={online} />
            <BalanceView amount={model.chips} />
            <IconButton icon="gear" label="Einstellungen" onClick={() => model.openSheet('settings')} />
          </div>

          <SectionLabel title="PLAY" detail={online ? undefined : 'OFFLINE MODE – alle Spiele lokal verfügbar'} />
          <div class="game-cards">
            <GameCard title="BLACKJACK" subtitle="Schlag den Dealer bis 21" onClick={() => model.navigate({ name: 'blackjack' })}>
              <div style={{ position: 'relative', width: 200, height: 150 }}>
                <FlatCard card={{ rank: 14, suit: 'spades' }} width={100} rotate={-12} style={{ position: 'absolute', left: 16, top: 0 }} />
                <FlatCard card={{ rank: 13, suit: 'hearts' }} width={100} rotate={10} style={{ position: 'absolute', left: 84, top: 6 }} />
              </div>
            </GameCard>
            <GameCard title="POKER" subtitle="Texas Hold'em gegen KI" onClick={() => model.navigate({ name: 'poker' })}>
              <div style={{ position: 'relative', width: 220, height: 150 }}>
                <div style={{ position: 'absolute', left: 6, top: 52 }}><ChipStack amount={6125} width={64} /></div>
                <FlatCard card={{ rank: 12, suit: 'diamonds' }} width={86} rotate={-8} style={{ position: 'absolute', left: 70, top: 4 }} />
                <FlatCard card={{ rank: 12, suit: 'clubs' }} width={86} rotate={9} style={{ position: 'absolute', left: 120, top: 10 }} />
              </div>
            </GameCard>
            <GameCard title="SLOTS" subtitle="3 Automaten · 10 Linien" onClick={() => model.navigate({ name: 'slotsLobby' })}>
              <div style={{ display: 'flex', gap: 8, padding: 12, borderRadius: 20, background: 'rgba(0,0,0,.4)', border: '2px solid var(--gold)' }}>
                {[0, 1, 2].map(() => <SlotSymbol id="seven" size={66} />)}
              </div>
            </GameCard>
          </div>

          <SectionLabel title="MULTIPLAYER" detail={online ? 'Online-Chips · vom Server verwaltet' : 'Benötigt eine Internetverbindung und einen Server'} />
          <div class="mp-cards">
            <MultiplayerCard icon="users" title="MIT FREUNDEN" subtitle="Raum erstellen oder per Code beitreten" enabled={online} onClick={() => openMultiplayer('friends')} />
            <MultiplayerCard icon="shuffle" title="RANDOM MATCH" subtitle="Echte Spieler finden – oder faire Bots" enabled={online} onClick={() => openMultiplayer('randomMatch')} />
          </div>

          <div class="extras">
            <ExtraCard icon="gift" title="DAILY REWARD" detail={model.canClaimDailyReward ? 'Jetzt abholen' : 'Morgen wieder'}
              badge={model.canClaimDailyReward ? '1' : undefined} onClick={() => model.openSheet('dailyReward')} />
            <ExtraCard icon="flag" title="MISSIONS" detail={`${missionsClaimed}/${p.dailyMissions.length} erledigt`}
              badge={missionsReady > 0 ? String(missionsReady) : undefined} onClick={() => model.openSheet('missions')} />
            <ExtraCard icon="trophy" title="ACHIEVEMENTS" detail={`${p.unlockedAchievements.size}/${RewardTable.achievements.length}`}
              badge={achievementsReady > 0 ? String(achievementsReady) : undefined} onClick={() => model.openSheet('achievements')} />
            <ExtraCard icon="chart" title="STATISTICS" detail={`${ChipFormat.string(p.stats.gamesPlayed)} Runden`} onClick={() => model.openSheet('statistics')} />
            <ExtraCard icon="gear" title="SETTINGS" detail="Regeln & Fairness" onClick={() => model.openSheet('settings')} />
            <ExtraCard icon="share" title="FREUNDE EINLADEN" detail="Link zur App teilen" onClick={invite} />
            {!isStandalone() && (
              <ExtraCard icon="download" title="ALS APP INSTALLIEREN" detail="Zum Home-Bildschirm" onClick={() => model.openSheet('install')} />
            )}
          </div>
          <NoCashValueNote />
        </div>
      </div>
      {offlineAlert && (
        <Dialog title="Keine Verbindung" message="Für Multiplayer wird eine Internetverbindung und ein erreichbarer BlackCasino-Server benötigt."
          actions={[{ label: 'OK', onClick: () => setOfflineAlert(false) }]} />
      )}
    </div>
  )
}

function SectionLabel({ title, detail }: { title: string; detail?: string }) {
  return (
    <div class="section-label">
      <span class="t">{title}</span>
      {detail && <span class="d">{detail}</span>}
    </div>
  )
}

function GameCard({ title, subtitle, onClick, children }: { title: string; subtitle: string; onClick: () => void; children: any }) {
  return (
    <button class="game-card" onClick={onClick} aria-label={title}>
      <div class="glow" />
      <div class="art">{children}</div>
      <div class="text">
        <h2 class="display">{title}</h2>
        <div class="sub"><span>{subtitle}</span><span class="go"><Icon name="back" size={18} stroke={3} style={{ transform: 'rotate(180deg)' }} /></span></div>
      </div>
    </button>
  )
}

function MultiplayerCard({ icon, title, subtitle, enabled, onClick }: { icon: IconName; title: string; subtitle: string; enabled: boolean; onClick: () => void }) {
  return (
    <button class={`mp-card glass ${enabled ? '' : 'off'}`} onClick={onClick} aria-label={title}>
      <div class="ic" style={enabled ? undefined : { color: 'var(--text-3)', background: 'rgba(219,18,41,.05)' }}><Icon name={icon} size={26} stroke={2.4} /></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <h3 class="display">{title}</h3>
        <p>{enabled ? subtitle : 'Offline nicht verfügbar'}</p>
      </div>
      <Icon name={enabled ? 'back' : 'wifiOff'} size={24} color={enabled ? 'var(--gold)' : 'var(--text-3)'} style={enabled ? { transform: 'rotate(180deg)' } : undefined} />
    </button>
  )
}

function ExtraCard({ icon, title, detail, badge, onClick }: { icon: IconName; title: string; detail: string; badge?: string; onClick: () => void }) {
  return (
    <button class="extra-card glass" onClick={onClick}>
      <div class="ic"><Icon name={icon} size={22} stroke={2.4} /></div>
      <div class="grow">
        <div class="t">{title}</div>
        <div class="d">{detail}</div>
      </div>
      {badge && <span class="count-badge">{badge}</span>}
    </button>
  )
}

/** Anleitung „Zum Home-Bildschirm“ – so wird BlackCasino auf dem iPad zur App. */
export function InstallGuide({ onClose }: { onClose: () => void }) {
  const steps: Array<[IconName, string]> = [
    ['link', 'Öffne den Link zu BlackCasino in Safari auf dem iPad.'],
    ['share', 'Tippe oben rechts auf das Teilen-Symbol (Quadrat mit Pfeil nach oben).'],
    ['plus', 'Wähle „Zum Home-Bildschirm“ und bestätige mit „Hinzufügen“.'],
    ['play', 'Starte BlackCasino ab jetzt über das neue Symbol – im Vollbild, ohne Browserleiste und auch offline.'],
  ]
  return (
    <div class="stack">
      <div class="sheet-header">
        <div style={{ flex: 1 }}>
          <h1 class="display">ALS APP INSTALLIEREN</h1>
          <p>BlackCasino läuft wie eine richtige App auf deinem iPad – kostenlos, ohne App Store.</p>
        </div>
        <IconButton icon="close" size={44} label="Schließen" onClick={onClose} />
      </div>
      {steps.map(([icon, text], i) => (
        <Glass radius={22} class="row-card">
          <div class="ic" style={{ color: 'var(--gold)' }}><Icon name={icon} size={26} /></div>
          <div class="grow" style={{ fontSize: 17, lineHeight: 1.45 }}><b style={{ color: 'var(--gold-light)' }}>{i + 1}.</b> {text}</div>
        </Glass>
      ))}
      <Glass radius={22} class="row-card">
        <div class="ic" style={{ color: 'var(--gold)' }}><Icon name="users" size={26} /></div>
        <div class="grow" style={{ fontSize: 16, lineHeight: 1.45, color: 'var(--text-2)' }}>
          Freunde einladen: Im Menü auf <b style={{ color: '#fff' }}>„Freunde einladen“</b> tippen und den Link per Nachricht schicken.
          Deine Freunde machen dann dieselben Schritte und haben BlackCasino ebenfalls als App.
        </div>
      </Glass>
      <NoCashValueNote />
    </div>
  )
}
