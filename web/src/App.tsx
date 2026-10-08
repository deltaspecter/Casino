import { useEffect, useMemo, useState } from 'preact/hooks'
import { AppModel } from './app/model'
import { useObserve } from './app/observable'
import { ConnectivityMonitor, OnlineService, healthURLFor, invitationID } from './net'
import { LoadingScreen } from './screens/Loading'
import { StartScreen } from './screens/Start'
import { MainMenu, InstallGuide } from './screens/Menu'
import { Achievements, DailyReward, LoginBonus, Missions, Settings, Statistics } from './screens/Sheets'
import { RulesSheet, TutorialSheet, type GameKind } from './screens/Rules'
import { FriendsHub, InvitationBanner, OnlineTable, RandomMatch } from './screens/Online'
import { BlackjackScreen, BlackjackViewModel } from './games/blackjack'
import { PokerScreen } from './games/poker'
import { SlotMachineScreen, SlotsLobby, computeSlotReports } from './games/slots'
import { Sheet } from './ui/components'
import { DealerHandDefs } from './ui/table'
import { Icon, type IconName } from './ui/icons'
import { RewardTable } from './core/progression'

export function App() {
  const model = useMemo(() => new AppModel(), [])
  const online = useMemo(() => new OnlineService(), [])
  const connectivity = useMemo(() => {
    const url = online.state.serverURL
    return new ConnectivityMonitor({ healthURL: url ? healthURLFor(url) : null })
  }, [])
  useObserve(model, online, connectivity)

  const [rules, setRules] = useState<GameKind | null>(null)
  const [tutorial, setTutorial] = useState<GameKind | null>(null)

  // Verbindung: Netz- und Serverstatus steuern den Online-Dienst automatisch.
  useEffect(() => {
    connectivity.start()
    const unbind = online.bindConnectivity(connectivity)
    const offEvents = online.subscribeEvents((event) => {
      if (event.type === 'notice') model.show({ icon: event.isError ? 'info' : 'sparkles', title: event.text, tint: event.isError ? 'red' : 'gold' })
    })
    document.documentElement.classList.toggle('reduced-motion', model.reducedMotion)
    return () => { unbind(); offEvents(); connectivity.stop() }
  }, [])

  // Online-Dienst verbinden, sobald die Lobby sichtbar ist und ein Server eingerichtet ist.
  useEffect(() => {
    if (model.phase === 'lobby' && online.state.serverURL && connectivity.state.browserOnline) online.connect(model.profile.displayName)
  }, [model.phase, online.state.serverURL])

  // Server hat einen Tisch zugewiesen (Raumstart oder Match): Tisch öffnen.
  const tableID = online.state.table?.tableID
  useEffect(() => {
    if (tableID && model.route.name !== 'onlineTable') model.navigate({ name: 'onlineTable' })
  }, [tableID])

  // Tutorial beim ersten Öffnen eines Spiels
  useEffect(() => {
    const game: GameKind | null = model.route.name === 'blackjack' ? 'blackjack' : model.route.name === 'poker' ? 'poker' : model.route.name === 'slotMachine' ? 'slots' : null
    if (game && !model.isTutorialCompleted(game)) setTutorial(game)
  }, [model.route.name])

  const isOnline = online.state.connection === 'online'
  const back = () => model.navigate({ name: 'menu' })
  const host = model
  const help = (game: GameKind) => () => setTutorial(game)

  let content
  if (model.phase === 'loading') {
    content = <LoadingScreen steps={[['Automaten werden kalibriert', () => computeSlotReports()]]} onFinished={() => model.setPhase('start')} />
  } else if (model.phase === 'start') {
    content = <StartScreen onPlay={() => { model.launchFinished(); model.setPhase('lobby') }} />
  } else {
    const r = model.route
    switch (r.name) {
      case 'blackjack':
        content = <BlackjackScreen host={host} chips={model.chips} onLeave={back} onRules={() => setRules('blackjack')} onHelp={help('blackjack')}
          onRecord={(e) => model.record({ type: 'blackjackRound', ...e })} onRescue={model.canClaimRescue ? () => model.claimRescue() : undefined} />
        break
      case 'poker':
        content = <PokerScreen host={host} chips={model.chips} playerName={() => model.profile.displayName}
          tableEscrow={() => model.profile.tableEscrow} setTableEscrow={(a) => model.setTableEscrow(a)}
          onLeave={back} onRules={() => setRules('poker')} onHelp={help('poker')}
          onRecord={(e) => model.record({ type: 'pokerHand', ...e })} onRescue={() => model.claimRescue()} canClaimRescue={model.canClaimRescue} />
        break
      case 'slotsLobby':
        content = <SlotsLobby chips={model.chips} onLeave={back} onOpen={(id) => model.navigate({ name: 'slotMachine', id })} />
        break
      case 'slotMachine':
        content = <SlotMachineScreen machineID={r.id} host={host} chips={model.chips} onLeave={() => model.navigate({ name: 'slotsLobby' })}
          onHelp={help('slots')} onRecord={(e) => model.record({ type: 'slotSpin', ...e })} onRescue={() => model.claimRescue()} canClaimRescue={model.canClaimRescue} />
        break
      case 'friends':
        content = <FriendsHub model={model} online={online} isOnline={isOnline} onBack={back} />
        break
      case 'randomMatch':
        content = <RandomMatch model={model} online={online} isOnline={isOnline} onBack={back} />
        break
      case 'onlineTable':
        content = <OnlineTable online={online} onRules={(g) => setRules(g)} onExit={back} />
        break
      default:
        content = <MainMenu model={model} online={isOnline} />
    }
  }

  const closeSheet = () => model.openSheet(null)
  const sheet = model.sheet
  const invitation = online.state.invitations[online.state.invitations.length - 1]
  const showLoginBonus = model.phase === 'lobby' && model.pendingLoginBonus && !sheet && model.route.name === 'menu'

  return (
    <>
      <DealerHandDefs />
      <div key={model.phase === 'lobby' ? model.route.name : model.phase} class="screen" style={{ animation: 'fade-in .45s ease-out' }}>
        {content}
      </div>

      {sheet && (
        <Sheet onClose={closeSheet}>
          {sheet === 'dailyReward' && <DailyReward model={model} onClose={closeSheet} />}
          {sheet === 'missions' && <Missions model={model} onClose={closeSheet} />}
          {sheet === 'achievements' && <Achievements model={model} onClose={closeSheet} />}
          {sheet === 'statistics' && <Statistics model={model} onClose={closeSheet} />}
          {sheet === 'settings' && <Settings model={model} online={online} isOnline={isOnline} onClose={closeSheet} />}
          {sheet === 'install' && <InstallGuide onClose={closeSheet} />}
        </Sheet>
      )}
      {showLoginBonus && (
        <Sheet medium dismissable={false} onClose={() => model.dismissLoginBonus()}>
          <LoginBonus model={model} offer={model.pendingLoginBonus!} />
        </Sheet>
      )}
      {rules && (
        <RulesSheet game={rules} onClose={() => setRules(null)}
          blackjack={{ minBet: BlackjackViewModel.tableRules.minBet, maxBet: BlackjackViewModel.tableRules.maxBet, maxHands: BlackjackViewModel.tableRules.maxHands }} />
      )}
      {tutorial && (
        <TutorialSheet game={tutorial} completed={model.isTutorialCompleted(tutorial)} reward={RewardTable.tutorialReward}
          onComplete={() => model.completeTutorial(tutorial)} onClose={() => setTutorial(null)} />
      )}
      {invitation && model.phase === 'lobby' && model.route.name !== 'onlineTable' && (
        <InvitationBanner key={invitationID(invitation)} online={online} invitation={invitation} />
      )}
      <div class="toasts" aria-live="polite">
        {model.toasts.map((t) => (
          <div class="toast glass" key={t.id}>
            <div class="ti" style={{ background: tintBg(t.tint), color: tintFg(t.tint) }}><Icon name={(t.icon as IconName) ?? 'info'} size={22} stroke={2.4} /></div>
            <div style={{ minWidth: 0 }}>
              <b>{t.title}</b>
              {t.subtitle && <span>{t.subtitle}</span>}
            </div>
          </div>
        ))}
      </div>
    </>
  )
}

const tintFg = (t?: string) => (t === 'red' ? 'var(--red-bright)' : t === 'green' ? 'var(--success)' : 'var(--gold)')
const tintBg = (t?: string) => (t === 'red' ? 'rgba(219,18,41,.15)' : t === 'green' ? 'rgba(64,217,128,.15)' : 'rgba(212,173,102,.15)')
