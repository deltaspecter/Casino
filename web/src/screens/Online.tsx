import { useEffect, useState } from 'preact/hooks'
import type { AppModel } from '../app/model'
import { useObserve } from '../app/observable'
import {
  ONLINE_GAME_INFO, ONLINE_GAMES, RoomCode, roomCanStart, type BlackjackAction, type Card as WireCard, type OnlineGame,
  type OnlineService, type PokerPlayerSnapshot, type RoomInfo, type TableSnapshot, type Invitation, type Presence,
  type BlackjackTableSnapshot, type PokerTableSnapshot,
} from '../net'
import { HandEvaluator, pokerActionKindTitle } from '../core/poker'
import { HandValue, handOutcomeTitle } from '../core/blackjack'
import { makeCard, type Suit } from '../core/cards'
import { Button, ChipIcon, ConnectionBadge, Glass, IconButton, InfoItem, ResultPill, SectionTitle, TableBar, TopBar, useNarrow } from '../ui/components'
import { Icon } from '../ui/icons'
import { ChipFormat } from '../ui/format'
import { DealerHand, Shoe, TableCard, TableChips, TablePlane, TableStage, reachPose, type CardFace } from '../ui/table'
import { serverStatusText } from './Sheets'

const SUITS: Suit[] = ['clubs', 'diamonds', 'hearts', 'spades']
const face = (c: WireCard): CardFace => ({ rank: c.rank, suit: SUITS[c.suit] ?? 'spades' })
const toCore = (cards: readonly WireCard[]) => cards.map((c) => makeCard(c.rank, SUITS[c.suit] ?? 'spades', c.deckIndex))
const gameTitle = (g: OnlineGame) => ONLINE_GAME_INFO[g].title

// ---------- Gemeinsame Bausteine ----------

function OnlineChips({ amount }: { amount: number }) {
  return (
    <div class="badge glass" style={{ gap: 8 }} aria-label={`Online-Chips ${amount}`}>
      <ChipIcon color="var(--gold)" size={20} />
      <div>
        <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 1, color: 'var(--text-3)' }}>ONLINE-CHIPS</div>
        <div class="numeric" style={{ fontSize: 17, fontWeight: 800 }}>{ChipFormat.string(amount)}</div>
      </div>
    </div>
  )
}

function MultiplayerHeader({ title, subtitle, online, isOnline, onBack }: {
  title: string; subtitle: string; online: OnlineService; isOnline: boolean; onBack: () => void
}) {
  useObserve(online)
  const account = online.state.account
  return (
    <TopBar title={title} subtitle={subtitle} onLeave={onBack}
      extra={<>{account && <OnlineChips amount={account.onlineChips} />}<ConnectionBadge online={isOnline} /></>} />
  )
}

function OfflineNotice({ online }: { online: OnlineService }) {
  useObserve(online)
  return (
    <Glass radius={24} style={{ padding: 22, display: 'flex', gap: 16, alignItems: 'center' }}>
      <Icon name="wifiOff" size={28} color="var(--text-2)" />
      <div>
        <div style={{ fontSize: 17, fontWeight: 700 }}>
          {online.state.serverURL ? 'Für Multiplayer wird eine Verbindung zum Server benötigt.' : 'Es ist noch kein Multiplayer-Server eingerichtet.'}
        </div>
        <div style={{ fontSize: 14, color: 'var(--text-2)', marginTop: 4 }}>
          {online.state.serverURL ? serverStatusText(online) + ' · ' : 'Die Adresse kann unter Settings eingetragen werden. '}
          Blackjack, Poker gegen KI und Slots kannst du jederzeit offline spielen.
        </div>
      </div>
    </Glass>
  )
}

function Segmented<T extends string>({ value, options, label, onChange }: { value: T; options: readonly T[]; label: (v: T) => string; onChange: (v: T) => void }) {
  return (
    <div class="segmented" style={{ display: 'flex' }}>
      {options.map((o) => <button style={{ flex: 1 }} class={o === value ? 'on' : ''} onClick={() => onChange(o)}>{label(o)}</button>)}
    </div>
  )
}

async function shareText(text: string, model: AppModel) {
  try {
    if (navigator.share) {
      await navigator.share({ text })
      return
    }
  } catch (e) {
    if ((e as Error).name === 'AbortError') return
  }
  try {
    await navigator.clipboard.writeText(text)
    model.show({ icon: 'copy', title: 'In die Zwischenablage kopiert' })
  } catch { /* nichts */ }
}

// ---------- Einladungen ----------

export function InvitationBanner({ online, invitation }: { online: OnlineService; invitation: Invitation }) {
  return (
    <div style={{ position: 'fixed', top: 'calc(12px + var(--safe-top))', left: '50%', transform: 'translateX(-50%)', zIndex: 90, width: 'min(620px, calc(100vw - 24px))', animation: 'toast-in .4s ease-out' }}>
      <Glass radius={24} style={{ padding: 14, display: 'flex', alignItems: 'center', gap: 14, boxShadow: '0 8px 20px rgba(0,0,0,.5)' }}>
        <Icon name="gift" size={24} color="var(--gold)" />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 16, fontWeight: 700 }}>{invitation.from.displayName} lädt dich ein</div>
          <div style={{ fontSize: 13, color: 'var(--text-2)' }}>{gameTitle(invitation.game)} · Raum {invitation.roomCode}</div>
        </div>
        <Button kind="ghost" size="small" onClick={() => online.decline(invitation)}>Ablehnen</Button>
        <Button kind="primary" size="small" onClick={() => online.accept(invitation)}>Beitreten</Button>
      </Glass>
    </div>
  )
}

// ---------- Mit Freunden ----------

export function FriendsHub({ model, online, isOnline, onBack }: { model: AppModel; online: OnlineService; isOnline: boolean; onBack: () => void }) {
  useObserve(online)
  const [joinCode, setJoinCode] = useState('')
  const [friendCode, setFriendCode] = useState('')
  const [createGame, setCreateGame] = useState<OnlineGame>('poker')
  useEffect(() => { online.connect(model.profile.displayName) }, [])
  const s = online.state
  const connected = s.connection === 'online'

  return (
    <div class="screen">
      <div class="light-sweep" />
      <div class="scroll">
        <div class="stack" style={{ padding: 'calc(96px + var(--safe-top)) calc(var(--gutter) + var(--safe-right)) 40px calc(var(--gutter) + var(--safe-left))', gap: 26 }}>
          {!isOnline ? <OfflineNotice online={online} /> : s.room ? <RoomLobby model={model} online={online} room={s.room} /> : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 20 }}>
              <Glass radius={26} style={{ padding: 22, display: 'flex', flexDirection: 'column', gap: 16 }}>
                <SectionTitle title="Raum erstellen" subtitle="Spiel wählen, Code teilen, Freunde warten lassen." />
                <Segmented value={createGame} options={ONLINE_GAMES} label={gameTitle} onChange={setCreateGame} />
                <div style={{ fontSize: 13, color: 'var(--text-3)' }}>
                  {gameTitle(createGame)}: {ONLINE_GAME_INFO[createGame].minPlayers}–{ONLINE_GAME_INFO[createGame].maxPlayers} Spieler
                </div>
                <Button kind="primary" size="large" full disabled={!connected} onClick={() => online.createRoom(createGame)}>RAUM ERSTELLEN</Button>
              </Glass>
              <Glass radius={26} style={{ padding: 22, display: 'flex', flexDirection: 'column', gap: 16 }}>
                <SectionTitle title="Raum beitreten" subtitle="Code vom Host eingeben." />
                <input class="text-input" value={joinCode} placeholder="z. B. A7K9P2" autocomplete="off" autocapitalize="characters" spellcheck={false}
                  style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 30, fontWeight: 900, textAlign: 'center', letterSpacing: 4 }}
                  onInput={(e) => setJoinCode([...(e.target as HTMLInputElement).value.toUpperCase()].filter((c) => RoomCode.alphabet.includes(c)).join('').slice(0, RoomCode.length))} />
                <Button kind="gold" size="large" full disabled={!connected || joinCode.length !== RoomCode.length}
                  onClick={() => {
                    if (!online.joinRoom(joinCode)) model.show({ icon: 'info', title: 'Ungültiger Code', subtitle: '6 Zeichen, z. B. A7K9P2', tint: 'red' })
                  }}>BEITRETEN</Button>
              </Glass>
            </div>
          )}

          <div class="stack" style={{ gap: 14 }}>
            <SectionTitle title="Friends" />
            {s.account && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', fontSize: 15 }}>
                <span style={{ color: 'var(--text-2)' }}>Dein Freundescode:</span>
                <span style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 900, fontSize: 20, color: 'var(--gold-light)' }}>{s.account.player.friendCode}</span>
                <IconButton icon="share" size={40} label="Freundescode teilen"
                  onClick={() => shareText(`Füge mich in BlackCasino als Freund hinzu: ${s.account!.player.friendCode}\n${location.origin + location.pathname}`, model)} />
                <span style={{ flex: 1 }} />
                <input class="text-input" style={{ width: 170, fontSize: 16, padding: '10px 12px' }} value={friendCode} placeholder="Freundescode"
                  autocomplete="off" autocapitalize="characters" spellcheck={false}
                  onInput={(e) => setFriendCode((e.target as HTMLInputElement).value.toUpperCase())} />
                <Button kind="secondary" size="small" disabled={friendCode.trim().length < RoomCode.length || !connected}
                  onClick={() => { online.addFriend(friendCode); setFriendCode('') }}>HINZUFÜGEN</Button>
              </div>
            )}
            {s.friends.length === 0 && (
              <div style={{ fontSize: 14, color: 'var(--text-3)' }}>Noch keine Freunde. Tausche Freundescodes aus, um sie zu Räumen einzuladen.</div>
            )}
            {s.friends.map((friend) => (
              <Glass radius={16} style={{ padding: 14, display: 'flex', alignItems: 'center', gap: 12 }}>
                <span class="dot" style={{ background: presenceColor(friend.presence) }} />
                <span style={{ fontSize: 17, fontWeight: 600 }}>{friend.player.displayName}</span>
                <span style={{ fontSize: 13, color: 'var(--text-2)' }}>{presenceLabel(friend.presence)}</span>
                <span style={{ flex: 1 }} />
                {s.room && friend.presence === 'online' && <Button kind="gold" size="small" onClick={() => online.invite(friend.player.id)}>EINLADEN</Button>}
                <IconButton icon="trash" size={38} label="Freund entfernen" onClick={() => online.removeFriend(friend.player.id)} />
              </Glass>
            ))}
          </div>
        </div>
      </div>
      <MultiplayerHeader title="MIT FREUNDEN" subtitle="Private Räume mit Einladungscode" online={online} isOnline={isOnline} onBack={onBack} />
    </div>
  )
}

const presenceColor = (p: Presence) => (p === 'online' ? 'var(--success)' : p === 'inGame' ? 'var(--gold)' : 'rgba(255,255,255,.3)')
const presenceLabel = (p: Presence) => (p === 'online' ? 'Online' : p === 'inGame' ? 'Im Spiel' : 'Offline')

function RoomLobby({ model, online, room }: { model: AppModel; online: OnlineService; room: RoomInfo }) {
  const me = online.state.account?.player.id
  const isHost = me === room.hostID
  const canStart = roomCanStart(room)
  const info = ONLINE_GAME_INFO[room.game]
  return (
    <Glass radius={28} style={{ padding: 26, display: 'flex', flexDirection: 'column', gap: 22 }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16, flexWrap: 'wrap' }}>
        <div style={{ flex: 1 }}>
          <div class="section-title" style={{ fontSize: 16 }}>BLACKCASINO ROOM</div>
          <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: 2, color: 'var(--text-3)', marginTop: 6 }}>ROOM CODE</div>
          <div class="gold-text" style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 900, fontSize: 'clamp(36px, 7vw, 54px)', letterSpacing: 8, userSelect: 'text', WebkitUserSelect: 'text' }}>{room.code}</div>
        </div>
        <Button kind="secondary" onClick={() => shareText(`Spiel mit mir ${info.title} in BlackCasino! Raumcode: ${room.code}\n${location.origin + location.pathname}`, model)}>
          <Icon name="share" size={18} /> CODE TEILEN
        </Button>
      </div>
      <div style={{ display: 'flex', gap: 30, flexWrap: 'wrap' }}>
        <InfoItem title="Spiel" value={info.title} />
        <InfoItem title="Spieler" value={`${room.members.length} / ${info.maxPlayers}`} />
        <InfoItem title="Status" value={room.status === 'waiting' ? (canStart ? 'Bereit' : 'Warte auf Spieler') : 'Im Spiel'} />
      </div>
      {isHost && room.members.length === 1 && (
        <div style={{ maxWidth: 320 }}><Segmented value={room.game} options={ONLINE_GAMES} label={gameTitle} onChange={(g) => online.setRoomGame(g)} /></div>
      )}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {room.members.map((m) => (
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 17, fontWeight: 600 }}>
            <Icon name={m.id === room.hostID ? 'crown' : 'person'} size={20} color={m.id === room.hostID ? 'var(--gold)' : 'var(--text-2)'} />
            {m.displayName}{m.id === me && <span style={{ color: 'var(--text-3)', fontWeight: 400 }}>(du)</span>}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 14, alignItems: 'center', flexWrap: 'wrap' }}>
        <Button kind="ghost" size="large" onClick={() => online.leaveRoom()}>RAUM VERLASSEN</Button>
        <span style={{ flex: 1 }} />
        {isHost
          ? <Button kind="primary" size="large" disabled={!canStart || online.state.connection !== 'online'} onClick={() => online.startRoom()}>START GAME</Button>
          : <span style={{ color: 'var(--text-2)', display: 'inline-flex', gap: 10, alignItems: 'center' }}><span class="spinner" /> Warte auf Host …</span>}
      </div>
      {isHost && !canStart && <div style={{ fontSize: 13, color: 'var(--text-3)' }}>Mindestens {info.minPlayers} Spieler werden benötigt.</div>}
    </Glass>
  )
}

// ---------- Random Match ----------

export function RandomMatch({ model, online, isOnline, onBack }: { model: AppModel; online: OnlineService; isOnline: boolean; onBack: () => void }) {
  useObserve(online)
  const [game, setGame] = useState<OnlineGame>('poker')
  const [, tick] = useState(0)
  useEffect(() => { online.connect(model.profile.displayName) }, [])
  useEffect(() => () => {
    const t = online.state.matchmaking.type
    if (t === 'searching' || t === 'noMatchFound') online.cancelMatch()
  }, [])
  const mm = online.state.matchmaking
  useEffect(() => {
    if (mm.type !== 'searching') return
    const t = window.setInterval(() => tick((n) => n + 1), 1000)
    return () => window.clearInterval(t)
  }, [mm.type])

  let body
  if (!isOnline) body = <OfflineNotice online={online} />
  else if (mm.type === 'searching') {
    body = (
      <Glass radius={30} style={{ padding: 34, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22, textAlign: 'center' }}>
        <span class="spinner large" />
        <div class="display" style={{ fontSize: 26 }}>Suche nach Spielern …</div>
        <div class="numeric" style={{ fontSize: 16, color: 'var(--text-2)' }}>{gameTitle(mm.game)} · {Math.max(0, Math.floor((Date.now() - mm.since) / 1000))} s</div>
        <Button kind="secondary" size="large" onClick={() => online.cancelMatch()}>ABBRECHEN</Button>
      </Glass>
    )
  } else if (mm.type === 'noMatchFound') {
    body = (
      <Glass radius={30} style={{ padding: 34, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20, textAlign: 'center' }}>
        <Icon name="users" size={40} color="var(--gold)" />
        <div class="display" style={{ fontSize: 22 }}>Kein Spieler gefunden. Mit Bots spielen?</div>
        <div style={{ display: 'flex', gap: 14 }}>
          <Button kind="primary" size="large" onClick={() => online.playWithBots()}>JA</Button>
          <Button kind="secondary" size="large" onClick={() => online.keepWaiting()}>WARTEN</Button>
        </div>
        <Button kind="ghost" size="small" onClick={() => online.cancelMatch()}>ABBRECHEN</Button>
      </Glass>
    )
  } else {
    body = (
      <Glass radius={30} style={{ padding: 30, display: 'flex', flexDirection: 'column', gap: 22 }}>
        <Segmented value={game} options={ONLINE_GAMES} label={gameTitle} onChange={setGame} />
        <div style={{ fontSize: 14, color: 'var(--text-2)' }}>
          {game === 'poker' ? "Texas Hold'em · Blinds 10/20 · Buy-in bis 2.000 Online-Chips" : 'Blackjack · gemeinsamer Dealer · Einsatz 10–1.000 Online-Chips'}
        </div>
        <Button kind="primary" size="large" full disabled={online.state.connection !== 'online'} onClick={() => online.findMatch(game)}>SPIELER SUCHEN</Button>
        <div style={{ fontSize: 14, color: 'var(--text-2)' }}>{serverStatusText(online)}</div>
      </Glass>
    )
  }
  return (
    <div class="screen">
      <div class="light-sweep" />
      <div class="scroll">
        <div style={{ minHeight: '100%', display: 'flex', flexDirection: 'column', padding: 'calc(96px + var(--safe-top)) calc(var(--gutter) + var(--safe-right)) calc(30px + var(--safe-bottom)) calc(var(--gutter) + var(--safe-left))' }}>
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ width: 'min(640px, 100%)' }}>{body}</div>
          </div>
          <div class="note" style={{ marginTop: 24 }}>Bots sehen nur ihre eigenen Karten und das, was alle am Tisch sehen. Sie beeinflussen weder Karten noch Ergebnisse.</div>
        </div>
      </div>
      <MultiplayerHeader title="RANDOM MATCH" subtitle="Zuerst echte Spieler, sonst auf Wunsch faire Bots" online={online} isOnline={isOnline} onBack={onBack} />
    </div>
  )
}

// ---------- Verbindungsverlust ----------

function ReconnectOverlay({ online, onGiveUp }: { online: OnlineService; onGiveUp: () => void }) {
  const s = online.state
  if (s.connection === 'reconnecting' || s.connection === 'connecting') {
    return (
      <div class="dialog" style={{ background: 'rgba(0,0,0,.7)' }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18, padding: 36 }}>
          <span class="spinner large" />
          <h2 class="display" style={{ fontSize: 26 }}>Verbindung verloren</h2>
          <p style={{ margin: 0 }}>Versuche Verbindung wiederherzustellen …<br />Der Spielstand bleibt auf dem Server erhalten.</p>
        </div>
      </div>
    )
  }
  if (s.connection === 'offline') {
    return (
      <div class="dialog" style={{ background: 'rgba(0,0,0,.7)' }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18, padding: 36 }}>
          <Icon name="wifiOff" size={44} color="var(--red-bright)" />
          <h2 class="display" style={{ fontSize: 22 }}>{s.failure ?? 'Verbindung getrennt'}</h2>
          <p style={{ margin: 0 }}>Offene Züge wurden vom Server nach den Tischregeln behandelt (Stand bzw. Check/Fold). Deine Online-Chips verwaltet weiterhin der Server.</p>
          <Button kind="primary" size="large" onClick={onGiveUp}>ZURÜCK ZUM MENÜ</Button>
        </div>
      </div>
    )
  }
  return null
}

function TurnTimer({ deadline }: { deadline: number | null }) {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    if (!deadline) return
    const t = window.setInterval(() => setNow(Date.now()), 500)
    return () => window.clearInterval(t)
  }, [deadline])
  if (!deadline) return null
  const remaining = Math.max(0, Math.ceil((deadline - now) / 1000))
  return (
    <div class="badge glass numeric" style={{ color: remaining <= 5 ? 'var(--red-bright)' : 'var(--text-2)' }}>
      <Icon name="hourglass" size={16} /> {remaining} s
    </div>
  )
}

// ---------- Online-Tisch ----------

/** Zeigt ausschließlich den vom Server gelieferten Zustand. Buttons senden nur Absichten. */
export function OnlineTable({ online, onRules, onExit }: { online: OnlineService; onRules: (game: OnlineGame) => void; onExit: () => void }) {
  useObserve(online)
  const table = online.state.table
  useEffect(() => {
    if (!table && online.state.tableClosedReason) onExit()
  }, [table, online.state.tableClosedReason])

  const leave = () => { online.leaveTable(); onExit() }
  const header = table && (
    <TopBar title={table.game === 'poker' ? 'ONLINE POKER' : 'ONLINE BLACKJACK'}
      subtitle={table.isPrivate ? 'Privater Raum · Server-autoritativ' : 'Öffentlicher Tisch · Server-autoritativ'}
      onLeave={leave} onRules={() => onRules(table.game)} extra={<TurnTimer deadline={table.turnDeadline} />} />
  )
  return (
    <div class="screen" style={{ display: 'flex', flexDirection: 'column', background: '#000' }}>
      {table?.blackjack ? <OnlineBlackjack online={online} table={table} bj={table.blackjack} header={header} />
        : table?.poker ? <OnlinePoker online={online} table={table} poker={table.poker} header={header} />
          : (
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16 }}>
              <span class="spinner" />
              <div style={{ color: 'var(--text-2)' }}>{online.state.tableClosedReason ?? 'Tisch wird geladen …'}</div>
              <Button kind="secondary" onClick={onExit}>ZURÜCK</Button>
            </div>
          )}
      <ReconnectOverlay online={online} onGiveUp={() => { online.acknowledgeFailure(); onExit() }} />
    </div>
  )
}

const seatName = (table: TableSnapshot, seatID: number) => table.seats.find((s) => s.seatID === seatID)
const SHOE = { x: 862, y: 236 }
// Ruhende Dealer-Hände (Nahsicht wie offline)
const BJ_HAND_L = reachPose({ x: 392, y: 252 }, { x: 300, y: -260 })
const BJ_HAND_R = reachPose({ x: 640, y: 246 }, { x: 700, y: -260 })
const PK_HAND_L = reachPose({ x: 428, y: 128 }, { x: 330, y: -320 })
const PK_HAND_R = reachPose({ x: 566, y: 124 }, { x: 670, y: -320 })

function Nameplate({ table, seatID, isMe, isTurn, detail, x, y }: {
  table: TableSnapshot; seatID: number; isMe: boolean; isTurn: boolean; detail?: string; x: number; y: number
}) {
  const seat = seatName(table, seatID)
  return (
    <div class={`seat-plate ${isTurn ? 'turn' : ''}`} style={{ left: x, top: y, minWidth: 120, borderColor: isMe && !isTurn ? 'rgba(212,173,102,.5)' : undefined }}>
      <b style={{ fontSize: 15 }}>
        {seat?.isBot && <span style={{ fontSize: 10, color: 'var(--gold-light)', marginRight: 6 }}>BOT</span>}
        {isMe ? 'Du' : seat?.player.displayName ?? '–'}
        {seat && !seat.isConnected && <Icon name="wifiOff" size={12} color="var(--red-bright)" style={{ marginLeft: 6 }} />}
      </b>
      {detail && <small>{detail}</small>}
    </div>
  )
}

function OnlineBlackjack({ online, table, bj, header }: { online: OnlineService; table: TableSnapshot; bj: BlackjackTableSnapshot; header: any }) {
  const [bet, setBet] = useState(50)
  const mySeat = bj.seats.find((s) => s.seatID === table.yourSeatID)
  const n = Math.max(1, bj.seats.length)
  const seatX = (i: number) => 500 + (i - (n - 1) / 2) * Math.min(200, 820 / n)
  const seatY = (i: number) => 520 + Math.abs(i - (n - 1) / 2) * -30
  const visibleDealer = bj.dealerCards.filter((c): c is WireCard => c !== null)
  const dealerValue = visibleDealer.length ? HandValue.display(HandValue.of(toCore(visibleDealer))) : null
  const myStake = mySeat ? (mySeat.hands.length ? mySeat.hands.reduce((s, h) => s + h.bet, 0) : mySeat.pendingBet ?? 0) : 0
  const settled = bj.phase === 'settled' && mySeat && mySeat.hands.length > 0 && mySeat.hands.every((h) => h.result)
  const net = settled ? mySeat!.hands.reduce((s, h) => s + (h.result!.payout - h.result!.stake), 0) : 0
  const current = bj.currentSeatID
  const narrow = useNarrow(900)

  return (
    <>
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex' }}>
        <TableStage width={1000} height={640} padTop={70} focusWidth={880}>
          <TablePlane kind="bj" top={-180} height={820} tilt={34}>
            <Shoe x={SHOE.x} y={SHOE.y - 6} />
            {bj.dealerCards.map((c, i) => (
              <TableCard key={`d${i}`} card={c ? face(c) : null} x={454 + i * 86} y={326} z={i + 1} from={SHOE} />
            ))}
            {bj.seats.map((seat, i) => {
              const isMe = seat.seatID === table.yourSeatID
              const cx = seatX(i), cy = seatY(i)
              const stake = seat.hands.length ? seat.hands.reduce((s, h) => s + h.bet, 0) : seat.pendingBet ?? 0
              const handCount = seat.hands.length
              return (
                <div key={seat.seatID}>
                  {seat.hands.map((hand, h) => {
                    const hx = cx + (h - (handCount - 1) / 2) * 84
                    const active = bj.currentSeatID === seat.seatID && bj.currentHandID === hand.id
                    return hand.cards.map((card, k) => (
                      <TableCard key={`s${seat.seatID}-h${hand.id}-${k}`} card={face(card)} width={isMe ? 84 : 70}
                        x={hx - 10 + k * 22} y={cy - k * 16} z={k + 1} rotate={hand.isDoubled && k === 2 ? 90 : 0} from={SHOE} highlight={active && handCount > 1} />
                    ))
                  })}
                  <TableChips amount={stake} x={cx} y={cy + 118} width={50} from={{ x: cx, y: 800 }} />
                  <Nameplate table={table} seatID={seat.seatID} isMe={isMe} isTurn={current === seat.seatID} x={cx} y={cy + 190}
                    detail={seat.hands.length === 1 ? (seat.hands[0].result ? handOutcomeTitle(seat.hands[0].result.outcome) : HandValue.display(HandValue.of(toCore(seat.hands[0].cards)))) : undefined} />
                </div>
              )
            })}
            <DealerHand pose={BJ_HAND_L} />
            <DealerHand pose={BJ_HAND_R} mirrored />
          </TablePlane>
        </TableStage>
        {header}
      </div>
      <TableBar info={<>
        {online.state.account && <InfoItem title="Online-Chips" value={ChipFormat.string(online.state.account.onlineChips)} />}
        <InfoItem title="Einsatz" value={ChipFormat.string(myStake)} />
        {dealerValue && <InfoItem title="Dealer" value={dealerValue} />}
        {mySeat && mySeat.hands.length > 0 && (
          <InfoItem title="Deine Hand" highlighted={current === table.yourSeatID}
            value={mySeat.hands.map((h) => (h.result ? handOutcomeTitle(h.result.outcome) : HandValue.display(HandValue.of(toCore(h.cards))))).join(' · ')} />
        )}
        {settled
          ? <ResultPill title={net > 0 ? 'GEWONNEN' : net < 0 ? 'VERLOREN' : 'PUSH'} net={net} />
          : current !== null && current !== table.yourSeatID && <span style={{ marginLeft: 'auto', fontSize: 14, fontWeight: 600, color: 'var(--text-2)', whiteSpace: 'nowrap' }}>{seatName(table, current)?.player.displayName} ist am Zug …</span>}
      </>}>
        {bj.bettingOpen
          ? mySeat?.pendingBet != null
            ? <div style={{ minHeight: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: 'var(--success)', fontWeight: 600 }}>
                <Icon name="checkCircle" size={20} /> Einsatz {ChipFormat.string(mySeat.pendingBet)} gesetzt – warte auf andere Spieler
              </div>
            : <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: narrow ? 'wrap' : 'nowrap' }}>
                <button class="step-btn" aria-label="Weniger" onClick={() => setBet(Math.max(bj.minBet, bet - 10))}><Icon name="minus" stroke={3} /></button>
                <div class="numeric" style={{ fontSize: 22, fontWeight: 800, minWidth: 140, textAlign: 'center' }}>Einsatz {ChipFormat.string(bet)}</div>
                <button class="step-btn" aria-label="Mehr" onClick={() => setBet(Math.min(bj.maxBet, bet + 10))}><Icon name="plus" stroke={3} /></button>
                <span style={{ flex: 1 }} />
                <Button kind="primary" size="large" disabled={!online.canAct} onClick={() => online.act({ type: 'placeBet', amount: Math.min(Math.max(bet, bj.minBet), bj.maxBet) })}>SETZEN</Button>
              </div>
          : bj.yourActions.length > 0
            ? <div class="controls-row">
                {(['hit', 'stand', 'double', 'split'] as BlackjackAction[]).map((a) => (
                  <Button kind={a === 'hit' ? 'primary' : a === 'double' ? 'gold' : 'secondary'} size="large"
                    disabled={!online.canAct || !bj.yourActions.includes(a)} onClick={() => online.act({ type: 'blackjack', action: a })}>
                    {a.toUpperCase()}
                  </Button>
                ))}
              </div>
            : <div style={{ minHeight: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-2)', fontWeight: 600 }}>
                {bj.phase === 'settled' ? 'Nächste Runde startet gleich …' : 'Warte auf den Server …'}
              </div>}
      </TableBar>
    </>
  )
}

function OnlinePoker({ online, table, poker, header }: { online: OnlineService; table: TableSnapshot; poker: PokerTableSnapshot; header: any }) {
  const [raiseTarget, setRaiseTarget] = useState(0)
  const legal = poker.yourLegalActions
  useEffect(() => { if (legal) setRaiseTarget(legal.minRaiseTo) }, [legal?.minRaiseTo, poker.handNumber, poker.street])
  const me = poker.players.find((p) => p.seatID === table.yourSeatID)
  const others = poker.players.filter((p) => p.seatID !== table.yourSeatID)
  const narrow = useNarrow(1000)

  // Sitzpositionen: du unten, die anderen gleichmäßig um den Tisch.
  const CX = 500, CY = 356, RX = 452, RY = 318
  const point = (angle: number, r = 1) => ({ x: CX + Math.cos((angle * Math.PI) / 180) * RX * r, y: CY + Math.sin((angle * Math.PI) / 180) * RY * r })
  const angleFor = (i: number) => 140 + ((i + 1) * 260) / (others.length + 1)
  const myHand = me?.holeCards && poker.community.length >= 3 && !me.hasFolded
    ? HandEvaluator.bestHand([...toCore(me.holeCards), ...toCore(poker.community)]).name : null
  const award = poker.awards[0]

  const detail = (p: PokerPlayerSnapshot) => {
    const show = poker.showdown.find((s) => s.seatID === p.seatID)
    if (show) return show.handName
    if (p.isSittingOut) return 'setzt aus'
    const parts = [ChipFormat.string(p.stack)]
    if (poker.buttonSeatID === p.seatID) parts.push('D')
    if (p.lastAction) parts.push(pokerActionKindTitle(p.lastAction.kind))
    return parts.join(' · ')
  }

  const target = Math.max(Math.round(raiseTarget), legal?.minRaiseTo ?? 0)
  const status = !poker.isHandInProgress
    ? poker.players.filter((p) => p.stack > 0).length < 2 ? 'Warte auf weitere Spieler …' : 'Nächste Hand startet gleich …'
    : poker.currentSeatID !== null ? `${seatName(table, poker.currentSeatID)?.player.displayName ?? ''} ist am Zug …` : ''

  return (
    <>
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex' }}>
        <TableStage width={1000} height={700} padTop={70}>
          <TablePlane kind="pk" top={-40} height={740} tilt={34}>
            {[0, 1, 2, 3, 4].map((i) => (
              <div style={{ position: 'absolute', left: 500 + (i - 2) * 104 - 46, top: 322 - 64, width: 92, height: 129, borderRadius: 7, border: '1.5px solid rgba(255,255,255,.12)' }} />
            ))}
            {poker.community.map((c, i) => <TableCard key={`c${i}`} card={face(c)} x={500 + (i - 2) * 104} y={322} width={92} z={1} from={{ x: 592, y: 118 }} />)}
            {poker.pot > 0 && <>
              <TableChips amount={poker.pot} x={500} y={478} width={52} />
              <div class="felt-label" style={{ left: 500, top: 522 }}>Pot {ChipFormat.string(poker.pot)}</div>
            </>}
            {others.map((p, i) => {
              const a = angleFor(i)
              const plate = point(a, 1.02)
              const cards = point(a, 0.74)
              const bet = point(a, 0.5)
              const faded = p.hasFolded || p.isSittingOut
              return (
                <div key={p.seatID} style={{ opacity: faded ? 0.5 : 1, transition: 'opacity .3s' }}>
                  {p.holeCards
                    ? p.holeCards.map((c, k) => <TableCard key={`o${p.seatID}-${poker.handNumber}-${k}`} card={face(c)} width={68} x={cards.x - 16 + k * 32} y={cards.y} rotate={k ? 6 : -7} z={k + 1} />)
                    : p.hasCards && [0, 1].map((k) => <TableCard key={`o${p.seatID}-${poker.handNumber}-${k}`} card={null} width={68} x={cards.x - 16 + k * 32} y={cards.y} rotate={k ? 6 : -7} z={k + 1} from={{ x: 592, y: 118 }} />)}
                  {p.streetBet > 0 && <TableChips amount={p.streetBet} x={bet.x} y={bet.y} width={44} />}
                  <Nameplate table={table} seatID={p.seatID} isMe={false} isTurn={poker.currentSeatID === p.seatID} detail={detail(p)} x={plate.x} y={plate.y} />
                </div>
              )
            })}
            {me && (() => {
              const cards = point(90, 0.78)
              const bet = point(90, 0.56)
              return (
                <div style={{ opacity: me.hasFolded ? 0.5 : 1 }}>
                  {(me.holeCards ?? []).map((c, k) => (
                    <TableCard key={`me-${poker.handNumber}-${k}`} card={face(c)} width={104} x={cards.x - 34 + k * 70} y={cards.y - 6} rotate={k ? 5 : -5} z={k + 1} from={{ x: 592, y: 118 }} />
                  ))}
                  {me.streetBet > 0 && <TableChips amount={me.streetBet} x={bet.x} y={bet.y} width={46} />}
                  {poker.buttonSeatID === me.seatID && (
                    <div class="seat-plate" style={{ left: cards.x + 130, top: cards.y, minWidth: 0, padding: 0, width: 38, height: 38, borderRadius: 19, background: 'linear-gradient(#fff,#ddd)', color: '#111', fontWeight: 900, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>D</div>
                  )}
                </div>
              )
            })()}
            <DealerHand pose={PK_HAND_L} width={110} />
            <DealerHand pose={PK_HAND_R} width={110} mirrored />
            <div class="shoe" style={{ left: 552, top: 94, width: 80, height: 50, transform: 'rotate(-8deg)' }} />
          </TablePlane>
        </TableStage>
        {header}
      </div>
      <TableBar info={<>
        {online.state.account && <InfoItem title="Online-Chips" value={ChipFormat.string(online.state.account.onlineChips)} />}
        <InfoItem title="Dein Stack" value={ChipFormat.string(me?.stack ?? 0)} />
        <InfoItem title="Einsatz" value={ChipFormat.string(me?.streetBet ?? 0)} />
        <InfoItem title="Pot" value={ChipFormat.string(poker.pot)} />
        {myHand && <InfoItem title="Deine Hand" value={myHand} color="var(--gold-light)" />}
        {award && (
          <div class="result-pill" style={{ color: award.seatID === table.yourSeatID ? 'var(--gold-light)' : 'var(--text-2)' }}>
            {award.seatID === table.yourSeatID ? 'Du gewinnst' : `${seatName(table, award.seatID)?.player.displayName ?? '?'} gewinnt`} {ChipFormat.string(award.amount)}{award.handName ? ` · ${award.handName}` : ''}
          </div>
        )}
      </>}>
        {legal ? (
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', justifyContent: 'flex-end', flexDirection: narrow ? 'column' : 'row', ...(narrow ? { alignItems: 'stretch' } : {}) }}>
            {legal.canRaise && legal.maxRaiseTo > legal.minRaiseTo && (
              <input type="range" class="slider" style={{ flex: 1, minWidth: 160, maxWidth: narrow ? undefined : 320 }} min={legal.minRaiseTo} max={legal.maxRaiseTo}
                step={Math.max(1, Math.min(poker.bigBlind, legal.maxRaiseTo - legal.minRaiseTo))} value={raiseTarget}
                onInput={(e) => setRaiseTarget(Number((e.target as HTMLInputElement).value))} />
            )}
            <div style={{ display: 'flex', gap: 12 }}>
              <Button kind="secondary" size="large" style={narrow ? { flex: 1 } : undefined} disabled={!online.canAct} onClick={() => online.act({ type: 'poker', action: { type: 'fold' } })}>FOLD</Button>
              {legal.canCheck
                ? <Button kind="secondary" size="large" style={narrow ? { flex: 1 } : undefined} disabled={!online.canAct} onClick={() => online.act({ type: 'poker', action: { type: 'check' } })}>CHECK</Button>
                : <Button kind="secondary" size="large" style={narrow ? { flex: 1 } : undefined} disabled={!online.canAct} onClick={() => online.act({ type: 'poker', action: { type: 'call' } })}>CALL {ChipFormat.string(legal.callAmount)}</Button>}
              {legal.canRaise && (
                <Button kind="primary" size="large" style={narrow ? { flex: 1.3 } : undefined} disabled={!online.canAct}
                  onClick={() => online.act({ type: 'poker', action: target >= legal.maxRaiseTo ? { type: 'allIn' } : { type: 'raise', to: target } })}>
                  {target >= legal.maxRaiseTo ? 'ALL-IN' : `${legal.canCheck ? 'BET' : 'RAISE'} ${ChipFormat.string(target)}`}
                </Button>
              )}
            </div>
          </div>
        ) : me && me.stack === 0 && !poker.isHandInProgress ? (
          <div class="controls-row" style={{ justifyContent: 'flex-end' }}>
            <Button kind="gold" size="large" style={{ flex: '0 1 auto' }} disabled={!online.canAct} onClick={() => online.act({ type: 'rebuy' })}>NACHKAUFEN</Button>
          </div>
        ) : (
          <div style={{ minHeight: 64, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', color: 'var(--text-2)', fontWeight: 600 }}>{status}</div>
        )}
      </TableBar>
    </>
  )
}
