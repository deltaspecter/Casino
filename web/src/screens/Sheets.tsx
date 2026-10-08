import { useEffect, useState } from 'preact/hooks'
import type { AppModel } from '../app/model'
import { useObserve } from '../app/observable'
import { PlayerProfile, RewardTable, type LoginBonusOffer, type MissionDefinition, type AchievementDefinition } from '../core/progression'
import {
  Button, ChipIcon, ConnectionBadge, Dialog, Glass, InfoBlock, NoCashValueNote, ProgressBar, SectionTitle, SheetHeader,
} from '../ui/components'
import { Icon, type IconName } from '../ui/icons'
import { ChipFormat, relativeTime } from '../ui/format'
import type { OnlineService } from '../net'

// ---------- Login-Bonus ----------

export function LoginBonus({ model, offer }: { model: AppModel; offer: LoginBonusOffer }) {
  const current = ((offer.streakDay - 1) % 7) + 1
  return (
    <div class="stack" style={{ alignItems: 'center', textAlign: 'center', gap: 24 }}>
      <h1 class="display" style={{ margin: 0, fontSize: 26 }}>WILLKOMMEN ZURÜCK</h1>
      <div style={{ fontSize: 16, color: 'var(--text-2)', fontWeight: 500 }}>Täglicher Login-Bonus · Tag {offer.streakDay}</div>
      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', justifyContent: 'center' }}>
        {[1, 2, 3, 4, 5, 6, 7].map((day) => (
          <div style={{
            padding: 10, borderRadius: 14, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
            background: day === current ? 'rgba(219,18,41,.18)' : 'var(--surface-raised)',
            border: `2px solid ${day === current ? 'var(--red)' : 'transparent'}`,
          }}>
            <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-2)' }}>TAG {day}</span>
            <ChipIcon size={34} color={day === current ? 'var(--red)' : day < current ? 'var(--gold)' : '#404040'} />
            <span class="numeric" style={{ fontSize: 13, fontWeight: 700 }}>{ChipFormat.compact(RewardTable.loginReward(day))}</span>
          </div>
        ))}
      </div>
      <Button kind="gold" size="large" onClick={() => model.claimLoginBonus()}>+{ChipFormat.string(offer.amount)} CHIPS ABHOLEN</Button>
      <NoCashValueNote compact />
    </div>
  )
}

// ---------- Tägliche Belohnung ----------

export function DailyReward({ model, onClose }: { model: AppModel; onClose: () => void }) {
  useObserve(model)
  const [, tick] = useState(0)
  useEffect(() => {
    const t = window.setInterval(() => tick((n) => n + 1), 30_000)
    return () => window.clearInterval(t)
  }, [])
  const can = model.canClaimDailyReward
  const next = model.profile.nextDailyReward(new Date())
  return (
    <div class="stack" style={{ alignItems: 'center', textAlign: 'center', gap: 28 }}>
      <div style={{ alignSelf: 'stretch', textAlign: 'left' }}>
        <SheetHeader title="DAILY REWARD" subtitle="Einmal pro Kalendertag kostenlose virtuelle Chips. Hat keinen Einfluss auf Spielergebnisse." onClose={onClose} />
      </div>
      <div style={{ position: 'relative', width: 260, height: 260, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: 'radial-gradient(circle, rgba(212,173,102,.4), transparent 70%)', animation: 'pulse-glow 3.6s ease-in-out infinite' }} />
        <Icon name={can ? 'gift' : 'checkCircle'} size={130} stroke={1.6} color="var(--gold-light)" style={{ filter: 'drop-shadow(0 0 30px rgba(212,173,102,.6))' }} />
      </div>
      <div class="display" style={{ fontSize: 40 }}>+{ChipFormat.string(RewardTable.dailyReward)} CHIPS</div>
      {can
        ? <Button kind="gold" size="large" onClick={() => model.claimDailyReward()}>JETZT ABHOLEN</Button>
        : next && (
          <div>
            <div style={{ fontSize: 18, fontWeight: 700 }}>Bereits abgeholt</div>
            <div style={{ fontSize: 15, color: 'var(--text-2)', marginTop: 6 }}>Nächste Belohnung {relativeTime(next)}</div>
          </div>
        )}
      {model.canClaimRescue && (
        <Glass radius={20} style={{ padding: 12, display: 'flex', alignItems: 'center', gap: 12 }}>
          <Icon name="lifebuoy" color="var(--gold)" />
          <span style={{ fontSize: 14, fontWeight: 600 }}>Zu wenig Chips? Hol dir ein kostenloses Startpaket.</span>
          <Button kind="gold" size="small" onClick={() => model.claimRescue()}>+{ChipFormat.string(RewardTable.rescueAmount)}</Button>
        </Glass>
      )}
      <NoCashValueNote />
    </div>
  )
}

// ---------- Missionen ----------

export function Missions({ model, onClose }: { model: AppModel; onClose: () => void }) {
  useObserve(model)
  return (
    <div class="stack">
      <SheetHeader title="MISSIONS" subtitle="Optionale Tagesaufgaben. Sie geben nur zusätzliche Chips – und verändern keine Gewinnchancen." onClose={onClose} />
      {model.profile.dailyMissions.map((mission) => {
        const def = RewardTable.mission(mission.missionID)
        return def && <MissionRow def={def} progress={mission.progress} claimed={mission.isClaimed} onClaim={() => model.claimMission(def.id)} />
      })}
      <div style={{ fontSize: 14, color: 'var(--text-3)' }}>Neue Missionen gibt es um Mitternacht.</div>
    </div>
  )
}

function MissionRow({ def, progress, claimed, onClaim }: { def: MissionDefinition; progress: number; claimed: boolean; onClaim: () => void }) {
  const complete = progress >= def.target
  return (
    <Glass radius={22} class="row-card">
      <div class="ic" style={{ color: claimed ? 'var(--success)' : complete ? 'var(--gold)' : 'var(--text-2)' }}>
        <Icon name={claimed ? 'checkCircle' : 'flag'} size={26} stroke={2.4} />
      </div>
      <div class="grow">
        <h3>{def.title}</h3>
        <ProgressBar value={progress / def.target} />
        <p>{ChipFormat.string(Math.min(progress, def.target))} / {ChipFormat.string(def.target)} · Belohnung {ChipFormat.string(def.rewardChips)} Chips</p>
      </div>
      {claimed
        ? <span style={{ fontSize: 13, fontWeight: 900, color: 'var(--success)' }}>EINGELÖST</span>
        : <Button kind="gold" size="small" disabled={!complete} onClick={onClaim}>EINLÖSEN</Button>}
    </Glass>
  )
}

// ---------- Erfolge ----------

const ACHIEVEMENT_ICONS: Record<string, IconName> = {
  'star.fill': 'star', 'suit.spade.fill': 'spade', 'trophy.fill': 'trophy', sparkles: 'sparkles',
  '100.circle.fill': 'medal', 'building.columns.fill': 'home', 'rectangle.stack.fill': 'copy', 'crown.fill': 'crown',
  'flame.fill': 'flame', 'diamond.fill': 'bolt', calendar: 'calendar',
}

export function Achievements({ model, onClose }: { model: AppModel; onClose: () => void }) {
  useObserve(model)
  const p = model.profile
  return (
    <div class="stack">
      <SheetHeader title="ACHIEVEMENTS"
        subtitle={`${p.unlockedAchievements.size} von ${RewardTable.achievements.length} freigeschaltet · reine Anzeige, ohne Einfluss auf das Spiel`} onClose={onClose} />
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 16 }}>
        {RewardTable.achievements.map((def) => (
          <AchievementTile def={def} value={p.metricValue(def.metric)} unlocked={p.unlockedAchievements.has(def.id)}
            claimed={p.claimedAchievements.has(def.id)} onClaim={() => model.claimAchievement(def.id)} />
        ))}
      </div>
    </div>
  )
}

function AchievementTile({ def, value, unlocked, claimed, onClaim }: {
  def: AchievementDefinition; value: number; unlocked: boolean; claimed: boolean; onClaim: () => void
}) {
  return (
    <Glass radius={22} style={{ padding: 18, display: 'flex', flexDirection: 'column', gap: 12, opacity: unlocked || value > 0 ? 1 : 0.75 }}>
      <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
        <div style={{
          width: 52, height: 52, borderRadius: '50%', flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: unlocked ? 'rgba(212,173,102,.14)' : 'rgba(255,255,255,.04)', color: unlocked ? 'var(--gold-light)' : 'var(--text-3)',
        }}>
          <Icon name={ACHIEVEMENT_ICONS[def.icon] ?? 'trophy'} size={24} stroke={2.4} />
        </div>
        <div>
          <div style={{ fontSize: 17, fontWeight: 700 }}>{def.title}</div>
          <div style={{ fontSize: 13, color: 'var(--text-2)', marginTop: 3 }}>{def.detail}</div>
        </div>
      </div>
      <ProgressBar value={value / def.threshold} height={6} gold={unlocked} />
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span class="numeric" style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-3)' }}>
          {ChipFormat.string(Math.min(value, def.threshold))} / {ChipFormat.string(def.threshold)}
        </span>
        {claimed
          ? <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--success)', display: 'inline-flex', gap: 4, alignItems: 'center' }}><Icon name="check" size={16} /> Erhalten</span>
          : unlocked
            ? <Button kind="gold" size="small" onClick={onClaim}>+{ChipFormat.string(def.rewardChips)}</Button>
            : <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-3)' }}>+{ChipFormat.string(def.rewardChips)}</span>}
      </div>
    </Glass>
  )
}

// ---------- Statistik ----------

function StatTile({ title, value, accent = false, color }: { title: string; value: string; accent?: boolean; color?: string }) {
  return (
    <Glass radius={18} class="tile">
      <small>{title}</small>
      <div class={accent ? 'gold-text' : ''} style={color ? { color } : undefined}>{value}</div>
    </Glass>
  )
}

/** Übersicht aller Spielstatistiken. Reine Anzeige – keine Engine liest diese Werte. */
export function Statistics({ model, onClose }: { model: AppModel; onClose: () => void }) {
  useObserve(model)
  const s = model.profile.stats
  return (
    <div class="stack" style={{ gap: 26 }}>
      <SheetHeader title="STATISTICS" subtitle="Dein bisheriges Spiel in Zahlen – nur zur Anzeige." onClose={onClose} />
      <div class="tiles">
        <StatTile title="Kontostand" value={ChipFormat.string(model.chips)} accent />
        <StatTile title="Höchster Kontostand" value={ChipFormat.string(s.peakChips)} />
        <StatTile title="Größter Gewinn" value={ChipFormat.string(s.biggestWin)} />
        <StatTile title="Gespielte Runden" value={ChipFormat.string(s.gamesPlayed)} />
      </div>
      <SectionTitle title="Gesamt" />
      <div class="tiles">
        <StatTile title="Gesamtgewinne" value={ChipFormat.string(s.totalWon)} color="var(--success)" />
        <StatTile title="Gesamtverluste" value={ChipFormat.string(s.totalLost)} color="var(--red-bright)" />
        <StatTile title="Saldo" value={ChipFormat.signed(s.netResult)} color={s.netResult >= 0 ? 'var(--success)' : 'var(--red-bright)'} />
        <StatTile title="Gesetzt gesamt" value={ChipFormat.string(s.totalWagered)} />
        <StatTile title="Gewonnene Runden" value={ChipFormat.string(s.roundsWon)} />
      </div>
      <SectionTitle title="Blackjack" />
      <div class="tiles">
        <StatTile title="Runden" value={ChipFormat.string(s.blackjackRounds)} />
        <StatTile title="Hände (inkl. Split)" value={ChipFormat.string(s.blackjackHands)} />
        <StatTile title="Gewonnene Hände" value={ChipFormat.string(s.blackjackWins)} />
        <StatTile title="Push" value={ChipFormat.string(s.blackjackPushes)} />
        <StatTile title="Blackjacks" value={ChipFormat.string(s.blackjacks)} />
      </div>
      <SectionTitle title="Poker" />
      <div class="tiles">
        <StatTile title="Runden" value={ChipFormat.string(s.pokerHands)} />
        <StatTile title="Gewonnene Pots" value={ChipFormat.string(s.pokerWins)} />
        <StatTile title="Gewinnquote" value={ChipFormat.percent(s.pokerWins, s.pokerHands)} />
      </div>
      <SectionTitle title="Slots" />
      <div class="tiles">
        <StatTile title="Spins" value={ChipFormat.string(s.slotSpins)} />
        <StatTile title="Gewinn-Spins" value={ChipFormat.string(s.slotWins)} />
        <StatTile title="Trefferquote" value={ChipFormat.percent(s.slotWins, s.slotSpins)} />
      </div>
      <NoCashValueNote />
    </div>
  )
}

// ---------- Einstellungen ----------

export function Settings({ model, online, isOnline, onClose }: { model: AppModel; online: OnlineService; isOnline: boolean; onClose: () => void }) {
  useObserve(model, online)
  const [name, setName] = useState(model.profile.displayName)
  const [serverURL, setServerURL] = useState(online.state.serverURL ?? '')
  const [confirmReset, setConfirmReset] = useState(false)
  const account = online.state.account
  const settings = model.profile.settings

  const commitName = () => {
    model.rename(name)
    setName(model.profile.displayName)
    online.rename(model.profile.displayName)
  }
  const commitServer = () => {
    const value = serverURL.trim()
    if ((online.state.serverURL ?? '') !== value) online.setServerURL(value || null)
  }

  return (
    <div class="stack" style={{ gap: 26 }}>
      <SheetHeader title="SETTINGS" subtitle="Profil, Darstellung und Informationen" onClose={() => { commitName(); commitServer(); onClose() }} />

      <SectionTitle title="Spielername" />
      <input class="text-input" value={name} maxLength={20} autocomplete="off" autocapitalize="words"
        onInput={(e) => setName((e.target as HTMLInputElement).value)}
        onBlur={commitName} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />

      <SectionTitle title="Darstellung" />
      <Glass radius={22}>
        <ToggleRow label="Reduzierte Effekte (schneller, akkuschonend)" on={settings.reducedMotion}
          onChange={(v) => model.updateSettings((s) => { s.reducedMotion = v })} />
      </Glass>

      <SectionTitle title="Online" subtitle="Multiplayer nutzt eigene Online-Chips, die ausschließlich der Server verwaltet – ebenfalls ohne Geldwert." />
      <Glass radius={22} style={{ padding: 18, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <ConnectionBadge online={isOnline} />
          <span style={{ fontSize: 14, color: 'var(--text-2)' }}>{serverStatusText(online)}</span>
        </div>
        {account && (
          <div style={{ display: 'flex', gap: 24, alignItems: 'center', flexWrap: 'wrap' }}>
            <div>
              <div class="label-caps" style={{ fontSize: 11 }}>FREUNDESCODE</div>
              <div style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 900, fontSize: 20, color: 'var(--gold-light)' }}>{account.player.friendCode}</div>
            </div>
            <div>
              <div class="label-caps" style={{ fontSize: 11 }}>ONLINE-CHIPS</div>
              <div class="numeric" style={{ fontWeight: 800, fontSize: 20 }}>{ChipFormat.string(account.onlineChips)}</div>
            </div>
            {account.onlineChips < 100 && <Button kind="gold" size="small" onClick={() => online.claimRescue()}>Online-Startpaket</Button>}
          </div>
        )}
        <div>
          <div class="label-caps" style={{ fontSize: 11 }}>SERVERADRESSE</div>
          <input class="text-input mono" value={serverURL} placeholder="wss://dein-server.onrender.com/ws" autocomplete="off" autocapitalize="off" spellcheck={false}
            inputMode="url" onInput={(e) => setServerURL((e.target as HTMLInputElement).value)} onBlur={commitServer}
            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
          <div style={{ fontSize: 12, color: 'var(--text-3)', marginTop: 6 }}>Nur ändern, wenn du einen eigenen BlackCasino-Server betreibst. Leer = nur offline spielen.</div>
        </div>
      </Glass>

      <SectionTitle title="Fairness & Zufall" />
      <InfoBlock icon="dice" text="Ablauf jeder Runde: Zufallsgenerator → Mischen bzw. Walzenstopp → Ausgabe → Spielregeln → Ergebnis. Verwendet wird der kryptografisch sichere Zufallsgenerator des Browsers (Web Crypto); Karten werden per Fisher-Yates gemischt." />
      <InfoBlock icon="lock" text="Es gibt keine Gewinn- oder Verlustserien-Steuerung, keine Anpassung an Kontostand, Verlauf, Uhrzeit, Missionen, Erfolge oder Daily Rewards. Die Spiel-Engines kennen dein Profil nicht." />
      <InfoBlock icon="film" text="Animationen zeigen nur Ergebnisse an, die vorher von der Spiel-Engine berechnet wurden. Sie entscheiden nichts." />
      <InfoBlock icon="cpu" text="Poker-Gegner sehen nur ihre eigenen Karten und das Board und können die Kartenverteilung nicht beeinflussen." />

      <SectionTitle title="Virtuelle Chips" />
      <InfoBlock icon="info" text="BlackCasino ist ein reines Unterhaltungsspiel. Chips sind virtuell und haben keinen realen Geldwert. Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen und keinen Umtausch in Geld, Kryptowährungen oder Sachwerte." />
      <InfoBlock icon="undo" text="Wird die App während einer Runde geschlossen, wird die unterbrochene Runde storniert und der Einsatz beim nächsten Start zurückgebucht." />
      <InfoBlock icon="home" text="Dein Spielstand wird nur auf diesem Gerät gespeichert. Tipp: Als App vom Home-Bildschirm gestartet, bleibt er dauerhaft erhalten." />

      <div><Button kind="ghost" onClick={() => setConfirmReset(true)}><Icon name="undo" size={18} /> Fortschritt zurücksetzen</Button></div>
      <div style={{ fontSize: 12, color: 'var(--text-3)' }}>BlackCasino Web {__APP_VERSION__}</div>

      {confirmReset && (
        <Dialog title="Gesamten Fortschritt löschen?"
          message={`Kontostand, Statistik, Missionen und Erfolge werden auf den Anfang gesetzt (${ChipFormat.string(PlayerProfile.startingChips)} Chips).`}
          actions={[
            { label: 'Abbrechen', onClick: () => setConfirmReset(false) },
            { label: 'Zurücksetzen', kind: 'primary', onClick: () => { model.resetProgress(); setName(model.profile.displayName); setConfirmReset(false) } },
          ]} />
      )}
    </div>
  )
}

function ToggleRow({ label, on, onChange }: { label: string; on: boolean; onChange: (v: boolean) => void }) {
  return (
    <button class="toggle-row" style={{ width: '100%', textAlign: 'left' }} role="switch" aria-checked={on} onClick={() => onChange(!on)}>
      <span>{label}</span>
      <span class={`switch ${on ? 'on' : ''}`} />
    </button>
  )
}

export function serverStatusText(online: OnlineService): string {
  const s = online.state
  if (!s.serverURL) return 'Kein Server eingerichtet – nur Offline-Spiele'
  switch (s.connection) {
    case 'online': return `Verbunden${s.latencyMs !== null && s.latencyMs !== undefined ? ` · ${Math.round(s.latencyMs)} ms` : ''}`
    case 'connecting': return 'Verbinde …'
    case 'reconnecting': return `Verbindung wird wiederhergestellt (Versuch ${s.reconnectAttempt}) …`
    default: return s.failure ?? 'Nicht verbunden'
  }
}
