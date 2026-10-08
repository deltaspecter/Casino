/**
 * Wire protocol of the BlackCasino game server (CasinoNet, protocol version 1).
 *
 * The server is written in Swift and uses the *synthesized* `Codable` conformances with
 * `JSONEncoder` / `JSONDecoder` and `dateEncodingStrategy = .millisecondsSince1970`.
 * That results in the following JSON conventions (verified against the real Swift encoder):
 *
 * - Enum cases with associated values: `{"caseName": {...}}`
 *   - labeled values use their label:   `{"rename":{"displayName":"Kim"}}`
 *   - unlabeled values use `_0`:        `{"hello":{"_0":{...}}}`
 *   - cases without values:             `{"ping":{}}`
 *   - an unlabeled `nil` optional is omitted: `{"room":{}}` (decoder also accepts `{"room":{"_0":null}}`)
 * - String raw-value enums: plain strings (`"poker"`, `"inGame"`, `"hit"`).
 * - Int raw-value enums: plain numbers (`Suit` 0…3, `Rank` 2…14, `PokerStreet` 0…4).
 * - `nil` struct properties are omitted (decoder accepts omitted or `null`).
 * - `nil` elements inside arrays are encoded as `null` (`dealerCards`).
 * - `Date`: milliseconds since 1970 as a JSON number (may be fractional).
 * - `UUID`: uppercase string `"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"` (decoder is case-insensitive).
 *
 * In TypeScript the messages are represented as discriminated unions with a `type` field;
 * `encode*` / `decode*` convert from/to the exact wire JSON. Decoding validates everything
 * and never throws – malformed input yields `null` (or an error result).
 *
 * The client never computes game results; these types are display data only.
 * All chips are virtual (no money value).
 */

export const PROTOCOL_VERSION = 1;
/** Same limit as `WireCodec.maxMessageBytes` on the server. */
export const MAX_MESSAGE_BYTES = 64 * 1024;

// MARK: - Basic types

export type OnlineGame = 'blackjack' | 'poker';
export const ONLINE_GAMES: readonly OnlineGame[] = ['blackjack', 'poker'];
export const ONLINE_GAME_INFO: Readonly<Record<OnlineGame, { title: string; minPlayers: number; maxPlayers: number }>> = {
  blackjack: { title: 'Blackjack', minPlayers: 2, maxPlayers: 5 },
  poker: { title: 'Poker', minPlayers: 2, maxPlayers: 6 },
};

export interface PlayerInfo {
  id: string;
  displayName: string;
  /** Short shareable code to add this player as a friend (empty for bots). */
  friendCode: string;
}

export type Presence = 'online' | 'offline' | 'inGame';

export interface FriendInfo {
  player: PlayerInfo;
  presence: Presence;
}

/** Online account. Online chips are managed only by the server and are purely virtual. */
export interface AccountInfo {
  player: PlayerInfo;
  onlineChips: number;
  /** Only set on first registration; the client stores it (localStorage). */
  token: string | null;
}

export type RoomStatus = 'waiting' | 'inGame';

export interface RoomInfo {
  code: string;
  game: OnlineGame;
  hostID: string;
  members: PlayerInfo[];
  status: RoomStatus;
}

export function roomCanStart(room: RoomInfo): boolean {
  return room.status === 'waiting' && room.members.length >= ONLINE_GAME_INFO[room.game].minPlayers;
}

export interface Invitation {
  roomCode: string;
  game: OnlineGame;
  from: PlayerInfo;
}

export function invitationID(inv: Invitation): string {
  return inv.roomCode + inv.from.id;
}

/** Swift `MatchmakingStatus`. `since` is milliseconds since 1970. */
export type MatchmakingStatus =
  | { type: 'searching'; game: OnlineGame; since: number }
  /** No suitable player after a short wait: the UI offers bots ("Kein Spieler gefunden. Mit Bots spielen?"). */
  | { type: 'noMatchFound'; game: OnlineGame }
  | { type: 'matched'; tableID: string }
  | { type: 'idle' };

// MARK: - Cards & game value types (as encoded by CasinoCore)

/** Swift `Suit: Int` – clubs=0, diamonds=1, hearts=2, spades=3. */
export type Suit = 0 | 1 | 2 | 3;
export const SUIT = { clubs: 0, diamonds: 1, hearts: 2, spades: 3 } as const;
/** Swift `Rank: Int` – two=2 … ten=10, jack=11, queen=12, king=13, ace=14. */
export type Rank = 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14;
export const RANK = { jack: 11, queen: 12, king: 13, ace: 14 } as const;

export interface Card {
  rank: Rank;
  suit: Suit;
  deckIndex: number;
}

export type HandOutcome = 'blackjack' | 'win' | 'push' | 'lose' | 'bust';
export interface HandResult {
  handID: number;
  outcome: HandOutcome;
  stake: number;
  /** Total payout including stake (0 on loss). */
  payout: number;
}

export type BlackjackPhase = 'betting' | 'playerTurn' | 'dealerTurn' | 'settled';
export type BlackjackAction = 'hit' | 'stand' | 'double' | 'split';

/** Swift `PokerStreet: Int` – preflop=0, flop=1, turn=2, river=3, showdown=4. */
export type PokerStreet = 0 | 1 | 2 | 3 | 4;
export const POKER_STREET = { preflop: 0, flop: 1, turn: 2, river: 3, showdown: 4 } as const;

export type PokerAction =
  | { type: 'fold' }
  | { type: 'check' }
  | { type: 'call' }
  /** Bet/raise to the total amount `to` in this betting round. */
  | { type: 'raise'; to: number }
  | { type: 'allIn' };

export type PokerActionKind = 'fold' | 'check' | 'call' | 'bet' | 'raise' | 'allIn' | 'smallBlind' | 'bigBlind';
export interface PokerActionRecord {
  kind: PokerActionKind;
  streetTotal: number;
}

export interface PokerLegalActions {
  canCheck: boolean;
  callAmount: number;
  canRaise: boolean;
  minRaiseTo: number;
  maxRaiseTo: number;
}

export interface PotAward {
  seatID: number;
  amount: number;
  potIndex: number;
  handName: string | null;
}

// MARK: - Table actions

export type TableAction =
  | { type: 'placeBet'; amount: number }
  | { type: 'blackjack'; action: BlackjackAction }
  | { type: 'poker'; action: PokerAction }
  | { type: 'rebuy' };

export interface TableActionRequest {
  /** Unique id (UUID); the server processes each id at most once. */
  actionID: string;
  /** Version of the snapshot the player decided on. */
  stateVersion: number;
  action: TableAction;
}

export interface ActionResult {
  actionID: string;
  accepted: boolean;
  reason: string | null;
}

// MARK: - Snapshots (per-recipient, redacted by the server)

export interface TableSeat {
  seatID: number;
  player: PlayerInfo;
  isBot: boolean;
  /** Display title of the bot's style (e.g. "Grundstrategie"), `null` for humans. */
  botStyle: string | null;
  isConnected: boolean;
}

export interface BlackjackHandSnapshot {
  id: number;
  cards: Card[];
  bet: number;
  isDoubled: boolean;
  result: HandResult | null;
}

export interface BlackjackSeatSnapshot {
  seatID: number;
  pendingBet: number | null;
  hands: BlackjackHandSnapshot[];
}

export interface BlackjackTableSnapshot {
  phase: BlackjackPhase;
  bettingOpen: boolean;
  /** Dealer cards; `null` is the face-down hole card. */
  dealerCards: (Card | null)[];
  seats: BlackjackSeatSnapshot[];
  currentSeatID: number | null;
  currentHandID: number | null;
  minBet: number;
  maxBet: number;
  /** Only for the recipient when it is their turn. */
  yourActions: BlackjackAction[];
  yourAdditionalStake: number;
}

export interface PokerPlayerSnapshot {
  seatID: number;
  stack: number;
  streetBet: number;
  hasFolded: boolean;
  isAllIn: boolean;
  isSittingOut: boolean;
  hasCards: boolean;
  /** Only own cards or cards revealed at showdown. */
  holeCards: Card[] | null;
  lastAction: PokerActionRecord | null;
}

export interface ShowdownSnapshot {
  seatID: number;
  handName: string;
}

export interface PokerTableSnapshot {
  handNumber: number;
  isHandInProgress: boolean;
  street: PokerStreet;
  community: Card[];
  pot: number;
  currentBet: number;
  smallBlind: number;
  bigBlind: number;
  buttonSeatID: number | null;
  currentSeatID: number | null;
  players: PokerPlayerSnapshot[];
  showdown: ShowdownSnapshot[];
  awards: PotAward[];
  yourLegalActions: PokerLegalActions | null;
}

export interface TableSnapshot {
  tableID: string;
  game: OnlineGame;
  /** Increases with every state change. */
  version: number;
  isPrivate: boolean;
  yourSeatID: number | null;
  seats: TableSeat[];
  /** Deadline (ms since 1970) for the player on turn. */
  turnDeadline: number | null;
  blackjack: BlackjackTableSnapshot | null;
  poker: PokerTableSnapshot | null;
}

// MARK: - Messages

export interface HelloRequest {
  token: string | null;
  displayName: string;
  protocolVersion: number;
}

export type ClientMessage =
  | { type: 'hello'; hello: HelloRequest }
  | { type: 'rename'; displayName: string }
  | { type: 'addFriend'; friendCode: string }
  | { type: 'removeFriend'; playerID: string }
  | { type: 'createRoom'; game: OnlineGame }
  | { type: 'joinRoom'; code: string }
  | { type: 'setRoomGame'; game: OnlineGame }
  | { type: 'startRoom' }
  | { type: 'leaveRoom' }
  | { type: 'inviteFriend'; playerID: string }
  | { type: 'findMatch'; game: OnlineGame }
  | { type: 'matchWithBots' }
  | { type: 'keepWaiting' }
  | { type: 'cancelMatch' }
  | { type: 'tableAction'; request: TableActionRequest }
  | { type: 'leaveTable' }
  | { type: 'claimOnlineRescue' }
  | { type: 'ping' };

export type ServerErrorCode =
  | 'notAuthenticated' | 'protocolMismatch' | 'invalidRequest'
  | 'roomNotFound' | 'roomFull' | 'roomAlreadyStarted' | 'notHost' | 'notEnoughPlayers' | 'alreadyInRoom'
  | 'friendNotFound' | 'insufficientChips' | 'notAtTable' | 'rateLimited';

export interface ServerError {
  code: ServerErrorCode;
  message: string;
}

export type ServerMessage =
  | { type: 'welcome'; account: AccountInfo }
  | { type: 'account'; account: AccountInfo }
  | { type: 'friends'; friends: FriendInfo[] }
  | { type: 'room'; room: RoomInfo | null }
  | { type: 'invitation'; invitation: Invitation }
  | { type: 'matchmaking'; status: MatchmakingStatus }
  | { type: 'table'; snapshot: TableSnapshot }
  | { type: 'tableClosed'; reason: string }
  | { type: 'actionResult'; result: ActionResult }
  | { type: 'notice'; text: string }
  | { type: 'error'; error: ServerError }
  | { type: 'pong' };

// MARK: - Exact wire shapes (what Swift's JSONEncoder produces)

type Empty = Record<string, never>;
export type WireCard = Card;
export type WirePokerAction =
  | { fold: Empty } | { check: Empty } | { call: Empty } | { raise: { to: number } } | { allIn: Empty };
export type WireTableAction =
  | { placeBet: { amount: number } }
  | { blackjack: { action: BlackjackAction } }
  | { poker: { action: WirePokerAction } }
  | { rebuy: Empty };
export interface WireTableActionRequest { actionID: string; stateVersion: number; action: WireTableAction }
export interface WireHelloRequest { token?: string; displayName: string; protocolVersion: number }
export type WireClientMessage =
  | { hello: { _0: WireHelloRequest } }
  | { rename: { displayName: string } }
  | { addFriend: { friendCode: string } }
  | { removeFriend: { playerID: string } }
  | { createRoom: { game: OnlineGame } }
  | { joinRoom: { code: string } }
  | { setRoomGame: { game: OnlineGame } }
  | { startRoom: Empty }
  | { leaveRoom: Empty }
  | { inviteFriend: { playerID: string } }
  | { findMatch: { game: OnlineGame } }
  | { matchWithBots: Empty }
  | { keepWaiting: Empty }
  | { cancelMatch: Empty }
  | { tableAction: { _0: WireTableActionRequest } }
  | { leaveTable: Empty }
  | { claimOnlineRescue: Empty }
  | { ping: Empty };
/** Struct optionals are omitted when nil (`?`), but `null` is accepted when decoding. */
type WireOpt<T> = T | null | undefined;
export type WireMatchmakingStatus =
  | { searching: { game: OnlineGame; since: number } }
  | { noMatchFound: { game: OnlineGame } }
  | { matched: { tableID: string } }
  | { idle: Empty };
export interface WireAccountInfo { player: PlayerInfo; onlineChips: number; token?: WireOpt<string> }
export type WireServerMessage =
  | { welcome: { _0: WireAccountInfo } }
  | { account: { _0: WireAccountInfo } }
  | { friends: { _0: FriendInfo[] } }
  | { room: { _0?: RoomInfo | null } }
  | { invitation: { _0: Invitation } }
  | { matchmaking: { _0: WireMatchmakingStatus } }
  | { table: { _0: unknown } }
  | { tableClosed: { reason: string } }
  | { actionResult: { _0: { actionID: string; accepted: boolean; reason?: WireOpt<string> } } }
  | { notice: { _0: string } }
  | { error: { _0: ServerError } }
  | { pong: Empty };

// MARK: - Validation helpers (internal)

class WireError extends Error {}

type Json = unknown;
type Obj = Record<string, Json>;

function fail(path: string, what: string): never {
  throw new WireError(`${path}: ${what}`);
}

function obj(v: Json, path: string): Obj {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) fail(path, 'expected object');
  return v as Obj;
}

function str(v: Json, path: string): string {
  if (typeof v !== 'string') fail(path, 'expected string');
  return v;
}

function bool(v: Json, path: string): boolean {
  if (typeof v !== 'boolean') fail(path, 'expected bool');
  return v;
}

/** Swift `Int` – rejects fractions, NaN and values outside the safe integer range. */
function int(v: Json, path: string): number {
  if (typeof v !== 'number' || !Number.isSafeInteger(v)) fail(path, 'expected integer');
  return v;
}

function num(v: Json, path: string): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) fail(path, 'expected number');
  return v;
}

function arr<T>(v: Json, path: string, item: (x: Json, p: string) => T): T[] {
  if (!Array.isArray(v)) fail(path, 'expected array');
  return v.map((x, i) => item(x, `${path}[${i}]`));
}

/** Optional property: missing or `null` → `null` (like `decodeIfPresent`). */
function opt<T>(o: Obj, key: string, path: string, item: (x: Json, p: string) => T): T | null {
  const v = o[key];
  return v === undefined || v === null ? null : item(v, `${path}.${key}`);
}

function oneOf<T extends string | number>(values: readonly T[]) {
  return (v: Json, path: string): T => {
    if (!(values as readonly Json[]).includes(v)) fail(path, `unexpected value ${JSON.stringify(v)}`);
    return v as T;
  };
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
function uuid(v: Json, path: string): string {
  const s = str(v, path);
  if (!UUID_RE.test(s)) fail(path, 'expected UUID');
  return s.toUpperCase();
}

/** Splits a Swift enum container `{"case": payload}` into case name and payload object. */
function enumCase(v: Json, path: string): [string, Obj] {
  const o = obj(v, path);
  const keys = Object.keys(o);
  if (keys.length !== 1) fail(path, 'expected exactly one enum case key');
  const name = keys[0]!;
  return [name, obj(o[name], `${path}.${name}`)];
}

const game = oneOf<OnlineGame>(ONLINE_GAMES);
const presence = oneOf<Presence>(['online', 'offline', 'inGame']);
const roomStatus = oneOf<RoomStatus>(['waiting', 'inGame']);
const suit = oneOf<Suit>([0, 1, 2, 3]);
const rank = oneOf<Rank>([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
const handOutcome = oneOf<HandOutcome>(['blackjack', 'win', 'push', 'lose', 'bust']);
const bjPhase = oneOf<BlackjackPhase>(['betting', 'playerTurn', 'dealerTurn', 'settled']);
const bjAction = oneOf<BlackjackAction>(['hit', 'stand', 'double', 'split']);
const pokerStreet = oneOf<PokerStreet>([0, 1, 2, 3, 4]);
const pokerActionKind = oneOf<PokerActionKind>(['fold', 'check', 'call', 'bet', 'raise', 'allIn', 'smallBlind', 'bigBlind']);
const errorCode = oneOf<ServerErrorCode>([
  'notAuthenticated', 'protocolMismatch', 'invalidRequest', 'roomNotFound', 'roomFull', 'roomAlreadyStarted',
  'notHost', 'notEnoughPlayers', 'alreadyInRoom', 'friendNotFound', 'insufficientChips', 'notAtTable', 'rateLimited',
]);

// MARK: - Struct decoders

function playerInfo(v: Json, p: string): PlayerInfo {
  const o = obj(v, p);
  return { id: str(o.id, `${p}.id`), displayName: str(o.displayName, `${p}.displayName`), friendCode: str(o.friendCode, `${p}.friendCode`) };
}

function friendInfo(v: Json, p: string): FriendInfo {
  const o = obj(v, p);
  return { player: playerInfo(o.player, `${p}.player`), presence: presence(o.presence, `${p}.presence`) };
}

function accountInfo(v: Json, p: string): AccountInfo {
  const o = obj(v, p);
  return { player: playerInfo(o.player, `${p}.player`), onlineChips: int(o.onlineChips, `${p}.onlineChips`), token: opt(o, 'token', p, str) };
}

function roomInfo(v: Json, p: string): RoomInfo {
  const o = obj(v, p);
  return {
    code: str(o.code, `${p}.code`),
    game: game(o.game, `${p}.game`),
    hostID: str(o.hostID, `${p}.hostID`),
    members: arr(o.members, `${p}.members`, playerInfo),
    status: roomStatus(o.status, `${p}.status`),
  };
}

function invitation(v: Json, p: string): Invitation {
  const o = obj(v, p);
  return { roomCode: str(o.roomCode, `${p}.roomCode`), game: game(o.game, `${p}.game`), from: playerInfo(o.from, `${p}.from`) };
}

function matchmakingStatus(v: Json, p: string): MatchmakingStatus {
  const [name, o] = enumCase(v, p);
  const q = `${p}.${name}`;
  switch (name) {
    case 'searching': return { type: 'searching', game: game(o.game, `${q}.game`), since: num(o.since, `${q}.since`) };
    case 'noMatchFound': return { type: 'noMatchFound', game: game(o.game, `${q}.game`) };
    case 'matched': return { type: 'matched', tableID: str(o.tableID, `${q}.tableID`) };
    case 'idle': return { type: 'idle' };
    default: return fail(p, `unknown matchmaking case ${name}`);
  }
}

function card(v: Json, p: string): Card {
  const o = obj(v, p);
  return { rank: rank(o.rank, `${p}.rank`), suit: suit(o.suit, `${p}.suit`), deckIndex: int(o.deckIndex, `${p}.deckIndex`) };
}

function cardOrNull(v: Json, p: string): Card | null {
  return v === null ? null : card(v, p);
}

function handResult(v: Json, p: string): HandResult {
  const o = obj(v, p);
  return {
    handID: int(o.handID, `${p}.handID`),
    outcome: handOutcome(o.outcome, `${p}.outcome`),
    stake: int(o.stake, `${p}.stake`),
    payout: int(o.payout, `${p}.payout`),
  };
}

function pokerAction(v: Json, p: string): PokerAction {
  const [name, o] = enumCase(v, p);
  switch (name) {
    case 'fold': case 'check': case 'call': case 'allIn': return { type: name };
    case 'raise': return { type: 'raise', to: int(o.to, `${p}.raise.to`) };
    default: return fail(p, `unknown poker action ${name}`);
  }
}

function tableAction(v: Json, p: string): TableAction {
  const [name, o] = enumCase(v, p);
  const q = `${p}.${name}`;
  switch (name) {
    case 'placeBet': return { type: 'placeBet', amount: int(o.amount, `${q}.amount`) };
    case 'blackjack': return { type: 'blackjack', action: bjAction(o.action, `${q}.action`) };
    case 'poker': return { type: 'poker', action: pokerAction(o.action, `${q}.action`) };
    case 'rebuy': return { type: 'rebuy' };
    default: return fail(p, `unknown table action ${name}`);
  }
}

function tableActionRequest(v: Json, p: string): TableActionRequest {
  const o = obj(v, p);
  return {
    actionID: uuid(o.actionID, `${p}.actionID`),
    stateVersion: int(o.stateVersion, `${p}.stateVersion`),
    action: tableAction(o.action, `${p}.action`),
  };
}

function actionResult(v: Json, p: string): ActionResult {
  const o = obj(v, p);
  return { actionID: uuid(o.actionID, `${p}.actionID`), accepted: bool(o.accepted, `${p}.accepted`), reason: opt(o, 'reason', p, str) };
}

function tableSeat(v: Json, p: string): TableSeat {
  const o = obj(v, p);
  return {
    seatID: int(o.seatID, `${p}.seatID`),
    player: playerInfo(o.player, `${p}.player`),
    isBot: bool(o.isBot, `${p}.isBot`),
    botStyle: opt(o, 'botStyle', p, str),
    isConnected: bool(o.isConnected, `${p}.isConnected`),
  };
}

function bjHand(v: Json, p: string): BlackjackHandSnapshot {
  const o = obj(v, p);
  return {
    id: int(o.id, `${p}.id`),
    cards: arr(o.cards, `${p}.cards`, card),
    bet: int(o.bet, `${p}.bet`),
    isDoubled: bool(o.isDoubled, `${p}.isDoubled`),
    result: opt(o, 'result', p, handResult),
  };
}

function bjSeat(v: Json, p: string): BlackjackSeatSnapshot {
  const o = obj(v, p);
  return { seatID: int(o.seatID, `${p}.seatID`), pendingBet: opt(o, 'pendingBet', p, int), hands: arr(o.hands, `${p}.hands`, bjHand) };
}

function bjTable(v: Json, p: string): BlackjackTableSnapshot {
  const o = obj(v, p);
  return {
    phase: bjPhase(o.phase, `${p}.phase`),
    bettingOpen: bool(o.bettingOpen, `${p}.bettingOpen`),
    dealerCards: arr(o.dealerCards, `${p}.dealerCards`, cardOrNull),
    seats: arr(o.seats, `${p}.seats`, bjSeat),
    currentSeatID: opt(o, 'currentSeatID', p, int),
    currentHandID: opt(o, 'currentHandID', p, int),
    minBet: int(o.minBet, `${p}.minBet`),
    maxBet: int(o.maxBet, `${p}.maxBet`),
    yourActions: arr(o.yourActions, `${p}.yourActions`, bjAction),
    yourAdditionalStake: int(o.yourAdditionalStake, `${p}.yourAdditionalStake`),
  };
}

function pokerPlayer(v: Json, p: string): PokerPlayerSnapshot {
  const o = obj(v, p);
  return {
    seatID: int(o.seatID, `${p}.seatID`),
    stack: int(o.stack, `${p}.stack`),
    streetBet: int(o.streetBet, `${p}.streetBet`),
    hasFolded: bool(o.hasFolded, `${p}.hasFolded`),
    isAllIn: bool(o.isAllIn, `${p}.isAllIn`),
    isSittingOut: bool(o.isSittingOut, `${p}.isSittingOut`),
    hasCards: bool(o.hasCards, `${p}.hasCards`),
    holeCards: opt(o, 'holeCards', p, (x, q) => arr(x, q, card)),
    lastAction: opt(o, 'lastAction', p, (x, q) => {
      const r = obj(x, q);
      return { kind: pokerActionKind(r.kind, `${q}.kind`), streetTotal: int(r.streetTotal, `${q}.streetTotal`) };
    }),
  };
}

function pokerTable(v: Json, p: string): PokerTableSnapshot {
  const o = obj(v, p);
  return {
    handNumber: int(o.handNumber, `${p}.handNumber`),
    isHandInProgress: bool(o.isHandInProgress, `${p}.isHandInProgress`),
    street: pokerStreet(o.street, `${p}.street`),
    community: arr(o.community, `${p}.community`, card),
    pot: int(o.pot, `${p}.pot`),
    currentBet: int(o.currentBet, `${p}.currentBet`),
    smallBlind: int(o.smallBlind, `${p}.smallBlind`),
    bigBlind: int(o.bigBlind, `${p}.bigBlind`),
    buttonSeatID: opt(o, 'buttonSeatID', p, int),
    currentSeatID: opt(o, 'currentSeatID', p, int),
    players: arr(o.players, `${p}.players`, pokerPlayer),
    showdown: arr(o.showdown, `${p}.showdown`, (x, q) => {
      const r = obj(x, q);
      return { seatID: int(r.seatID, `${q}.seatID`), handName: str(r.handName, `${q}.handName`) };
    }),
    awards: arr(o.awards, `${p}.awards`, (x, q) => {
      const r = obj(x, q);
      return {
        seatID: int(r.seatID, `${q}.seatID`),
        amount: int(r.amount, `${q}.amount`),
        potIndex: int(r.potIndex, `${q}.potIndex`),
        handName: opt(r, 'handName', q, str),
      };
    }),
    yourLegalActions: opt(o, 'yourLegalActions', p, (x, q) => {
      const r = obj(x, q);
      return {
        canCheck: bool(r.canCheck, `${q}.canCheck`),
        callAmount: int(r.callAmount, `${q}.callAmount`),
        canRaise: bool(r.canRaise, `${q}.canRaise`),
        minRaiseTo: int(r.minRaiseTo, `${q}.minRaiseTo`),
        maxRaiseTo: int(r.maxRaiseTo, `${q}.maxRaiseTo`),
      };
    }),
  };
}

function tableSnapshot(v: Json, p: string): TableSnapshot {
  const o = obj(v, p);
  return {
    tableID: str(o.tableID, `${p}.tableID`),
    game: game(o.game, `${p}.game`),
    version: int(o.version, `${p}.version`),
    isPrivate: bool(o.isPrivate, `${p}.isPrivate`),
    yourSeatID: opt(o, 'yourSeatID', p, int),
    seats: arr(o.seats, `${p}.seats`, tableSeat),
    turnDeadline: opt(o, 'turnDeadline', p, num),
    blackjack: opt(o, 'blackjack', p, bjTable),
    poker: opt(o, 'poker', p, pokerTable),
  };
}

function helloRequest(v: Json, p: string): HelloRequest {
  const o = obj(v, p);
  return {
    token: opt(o, 'token', p, str),
    displayName: str(o.displayName, `${p}.displayName`),
    protocolVersion: int(o.protocolVersion, `${p}.protocolVersion`),
  };
}

// MARK: - Message decoding

/** Result of decoding with an error description for logging (never thrown). */
export type DecodeResult<T> = { ok: true; value: T } | { ok: false; error: string };

function utf8Length(text: string): number {
  // Fast path: every UTF-16 code unit is at most 3 UTF-8 bytes.
  if (text.length * 3 <= MAX_MESSAGE_BYTES) return text.length;
  return new TextEncoder().encode(text).length;
}

function parse<T>(text: unknown, decode: (v: Json, p: string) => T): DecodeResult<T> {
  try {
    if (typeof text !== 'string') return { ok: false, error: 'message is not text' };
    if (utf8Length(text) > MAX_MESSAGE_BYTES) return { ok: false, error: 'message too large' };
    return { ok: true, value: decode(JSON.parse(text) as Json, '$') };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

function serverMessage(v: Json, p: string): ServerMessage {
  const [name, o] = enumCase(v, p);
  const q = `${p}.${name}`;
  switch (name) {
    case 'welcome': return { type: 'welcome', account: accountInfo(o._0, `${q}._0`) };
    case 'account': return { type: 'account', account: accountInfo(o._0, `${q}._0`) };
    case 'friends': return { type: 'friends', friends: arr(o._0, `${q}._0`, friendInfo) };
    case 'room': return { type: 'room', room: opt(o, '_0', q, roomInfo) };
    case 'invitation': return { type: 'invitation', invitation: invitation(o._0, `${q}._0`) };
    case 'matchmaking': return { type: 'matchmaking', status: matchmakingStatus(o._0, `${q}._0`) };
    case 'table': return { type: 'table', snapshot: tableSnapshot(o._0, `${q}._0`) };
    case 'tableClosed': return { type: 'tableClosed', reason: str(o.reason, `${q}.reason`) };
    case 'actionResult': return { type: 'actionResult', result: actionResult(o._0, `${q}._0`) };
    case 'notice': return { type: 'notice', text: str(o._0, `${q}._0`) };
    case 'error': {
      const e = obj(o._0, `${q}._0`);
      return { type: 'error', error: { code: errorCode(e.code, `${q}._0.code`), message: str(e.message, `${q}._0.message`) } };
    }
    case 'pong': return { type: 'pong' };
    default: return fail(p, `unknown server message ${name}`);
  }
}

function clientMessage(v: Json, p: string): ClientMessage {
  const [name, o] = enumCase(v, p);
  const q = `${p}.${name}`;
  switch (name) {
    case 'hello': return { type: 'hello', hello: helloRequest(o._0, `${q}._0`) };
    case 'rename': return { type: 'rename', displayName: str(o.displayName, `${q}.displayName`) };
    case 'addFriend': return { type: 'addFriend', friendCode: str(o.friendCode, `${q}.friendCode`) };
    case 'removeFriend': return { type: 'removeFriend', playerID: str(o.playerID, `${q}.playerID`) };
    case 'createRoom': return { type: 'createRoom', game: game(o.game, `${q}.game`) };
    case 'joinRoom': return { type: 'joinRoom', code: str(o.code, `${q}.code`) };
    case 'setRoomGame': return { type: 'setRoomGame', game: game(o.game, `${q}.game`) };
    case 'inviteFriend': return { type: 'inviteFriend', playerID: str(o.playerID, `${q}.playerID`) };
    case 'findMatch': return { type: 'findMatch', game: game(o.game, `${q}.game`) };
    case 'tableAction': return { type: 'tableAction', request: tableActionRequest(o._0, `${q}._0`) };
    case 'startRoom': case 'leaveRoom': case 'matchWithBots': case 'keepWaiting': case 'cancelMatch':
    case 'leaveTable': case 'claimOnlineRescue': case 'ping':
      return { type: name };
    default: return fail(p, `unknown client message ${name}`);
  }
}

/** Decodes a server message; `null` for anything malformed (never throws). */
export function decodeServerMessage(text: unknown): ServerMessage | null {
  const r = parse(text, serverMessage);
  return r.ok ? r.value : null;
}

export function decodeServerMessageResult(text: unknown): DecodeResult<ServerMessage> {
  return parse(text, serverMessage);
}

/** Decodes a client message (used by tests and fake servers). */
export function decodeClientMessage(text: unknown): ClientMessage | null {
  const r = parse(text, clientMessage);
  return r.ok ? r.value : null;
}

export function decodeClientMessageResult(text: unknown): DecodeResult<ClientMessage> {
  return parse(text, clientMessage);
}

// MARK: - Encoding

const EMPTY: Empty = {};

export function toWirePokerAction(a: PokerAction): WirePokerAction {
  switch (a.type) {
    case 'raise': return { raise: { to: a.to } };
    case 'fold': return { fold: EMPTY };
    case 'check': return { check: EMPTY };
    case 'call': return { call: EMPTY };
    case 'allIn': return { allIn: EMPTY };
  }
}

export function toWireTableAction(a: TableAction): WireTableAction {
  switch (a.type) {
    case 'placeBet': return { placeBet: { amount: a.amount } };
    case 'blackjack': return { blackjack: { action: a.action } };
    case 'poker': return { poker: { action: toWirePokerAction(a.action) } };
    case 'rebuy': return { rebuy: EMPTY };
  }
}

export function toWireClientMessage(m: ClientMessage): WireClientMessage {
  switch (m.type) {
    case 'hello': {
      const h: WireHelloRequest = { displayName: m.hello.displayName, protocolVersion: m.hello.protocolVersion };
      if (m.hello.token !== null) h.token = m.hello.token;
      return { hello: { _0: h } };
    }
    case 'rename': return { rename: { displayName: m.displayName } };
    case 'addFriend': return { addFriend: { friendCode: m.friendCode } };
    case 'removeFriend': return { removeFriend: { playerID: m.playerID } };
    case 'createRoom': return { createRoom: { game: m.game } };
    case 'joinRoom': return { joinRoom: { code: m.code } };
    case 'setRoomGame': return { setRoomGame: { game: m.game } };
    case 'inviteFriend': return { inviteFriend: { playerID: m.playerID } };
    case 'findMatch': return { findMatch: { game: m.game } };
    case 'tableAction':
      return { tableAction: { _0: {
        actionID: m.request.actionID.toUpperCase(),
        stateVersion: m.request.stateVersion,
        action: toWireTableAction(m.request.action),
      } } };
    case 'startRoom': return { startRoom: EMPTY };
    case 'leaveRoom': return { leaveRoom: EMPTY };
    case 'matchWithBots': return { matchWithBots: EMPTY };
    case 'keepWaiting': return { keepWaiting: EMPTY };
    case 'cancelMatch': return { cancelMatch: EMPTY };
    case 'leaveTable': return { leaveTable: EMPTY };
    case 'claimOnlineRescue': return { claimOnlineRescue: EMPTY };
    case 'ping': return { ping: EMPTY };
  }
}

/** Encodes a client message as wire JSON text. */
export function encodeClientMessage(m: ClientMessage): string {
  return JSON.stringify(toWireClientMessage(m));
}

/** Removes `null` struct properties recursively (Swift omits nil optionals) – arrays keep `null`. */
function omitNulls(v: unknown): unknown {
  if (Array.isArray(v)) return v.map((x) => (x === null ? null : omitNulls(x)));
  if (typeof v === 'object' && v !== null) {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v)) if (x !== null && x !== undefined) out[k] = omitNulls(x);
    return out;
  }
  return v;
}

function toWireMatchmaking(s: MatchmakingStatus): WireMatchmakingStatus {
  switch (s.type) {
    case 'searching': return { searching: { game: s.game, since: s.since } };
    case 'noMatchFound': return { noMatchFound: { game: s.game } };
    case 'matched': return { matched: { tableID: s.tableID } };
    case 'idle': return { idle: EMPTY };
  }
}

/** Server-side encoding (for fake servers in tests / tooling); mirrors Swift's output. */
export function toWireServerMessage(m: ServerMessage): WireServerMessage {
  switch (m.type) {
    case 'welcome': return { welcome: { _0: omitNulls(m.account) as WireAccountInfo } };
    case 'account': return { account: { _0: omitNulls(m.account) as WireAccountInfo } };
    case 'friends': return { friends: { _0: m.friends } };
    case 'room': return { room: m.room === null ? {} : { _0: m.room } };
    case 'invitation': return { invitation: { _0: m.invitation } };
    case 'matchmaking': return { matchmaking: { _0: toWireMatchmaking(m.status) } };
    case 'table': return { table: { _0: omitNulls(m.snapshot) } };
    case 'tableClosed': return { tableClosed: { reason: m.reason } };
    case 'actionResult': return { actionResult: { _0: omitNulls(m.result) as { actionID: string; accepted: boolean } } };
    case 'notice': return { notice: { _0: m.text } };
    case 'error': return { error: { _0: m.error } };
    case 'pong': return { pong: EMPTY };
  }
}

export function encodeServerMessage(m: ServerMessage): string {
  return JSON.stringify(toWireServerMessage(m));
}
