/**
 * Client for the BlackCasino server (WebSocket) – port of the native `OnlineService.swift`.
 *
 * Principle: the server is the source of truth. This client only sends intents and shows the
 * received state. It never creates cards, winners, bets or balances itself – not even on
 * connection loss. All chips are virtual (entertainment only, no money value).
 *
 * Framework-agnostic: `state` is an immutable snapshot replaced on every change;
 * `subscribe(listener)` notifies about state changes, `subscribeEvents(listener)` about
 * transient events (notices/errors, invitations, action results).
 */

import { ActionGate, ReconnectPolicy, RoomCode, makeUUID } from './clientSupport';
import {
  type KeyValueStorage, defaultStorage, getServerURL, isBlockedMixedContent, normalizeServerURL,
  safeGet, safeSet, setServerURLOverride,
} from './config';
import type { ConnectivityMonitor } from './connectivity';
import {
  PROTOCOL_VERSION, decodeServerMessage, encodeClientMessage,
  type AccountInfo, type ActionResult, type ClientMessage, type FriendInfo, type Invitation, type MatchmakingStatus,
  type OnlineGame, type RoomInfo, type ServerError, type ServerMessage, type TableAction, type TableSnapshot,
  invitationID,
} from './protocol';

export type ConnectionStatus = 'offline' | 'connecting' | 'online' | 'reconnecting';

export interface OnlineState {
  /** offline = not connected (see `failure`), connecting = first attempt, online = welcomed, reconnecting = lost, retrying. */
  readonly connection: ConnectionStatus;
  /** Current reconnect attempt (0-based) while `connection === 'reconnecting'`, else 0. */
  readonly reconnectAttempt: number;
  /** Why the service is offline after giving up (reconnect exhausted, invalid URL, outdated protocol). */
  readonly failure: string | null;
  /** Normalized `ws(s)://…/ws` URL, `null` = no server configured (offline-only app). */
  readonly serverURL: string | null;
  readonly account: AccountInfo | null;
  readonly friends: readonly FriendInfo[];
  readonly room: RoomInfo | null;
  readonly matchmaking: MatchmakingStatus;
  readonly table: TableSnapshot | null;
  readonly invitations: readonly Invitation[];
  /** Last reason a table was closed (for a hint); cleared by the next snapshot or `clearClosedReason()`. */
  readonly tableClosedReason: string | null;
  /** Id of the unconfirmed table action (double-tap protection). */
  readonly pendingActionID: string | null;
  /** Connected and no action pending. */
  readonly canAct: boolean;
  /** Last measured round-trip time of ping/pong in ms. */
  readonly latencyMs: number | null;
}

export type OnlineEvent =
  /** User-facing message (server notice, error, rejected action). Mirrors Swift `onNotice(text, isError)`. */
  | { type: 'notice'; text: string; isError: boolean }
  | { type: 'error'; error: ServerError }
  | { type: 'invitation'; invitation: Invitation }
  | { type: 'actionResult'; result: ActionResult }
  | { type: 'tableClosed'; reason: string }
  /** No player found yet: offer bots ("Kein Spieler gefunden. Mit Bots spielen?"). */
  | { type: 'botOffer'; game: OnlineGame };

/** Text for the bot offer dialog in random matchmaking. */
export const BOT_OFFER_TEXT = 'Kein Spieler gefunden. Mit Bots spielen?';
export const TOKEN_STORAGE_KEY = 'blackcasino.online.token';
/** Failure text when the same account connected from another tab or device. */
export const SESSION_TAKEN_OVER_TEXT = 'Die Online-Sitzung wurde in einem anderen Fenster oder auf einem anderen Gerät geöffnet.';

/** Minimal WebSocket surface (browser `WebSocket` satisfies it; tests use a fake). */
export interface WebSocketLike {
  readonly readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  onopen: ((ev: Event) => unknown) | null;
  onmessage: ((ev: MessageEvent) => unknown) | null;
  onclose: ((ev: CloseEvent) => unknown) | null;
  onerror: ((ev: Event) => unknown) | null;
}

const WS_OPEN = 1;

export interface OnlineServiceOptions {
  /** Server WebSocket URL; default: `getServerURL()` (localStorage override, then VITE_SERVER_URL). `null` = none. */
  serverURL?: string | null;
  /** Token storage (default `localStorage`). */
  storage?: KeyValueStorage | null;
  createWebSocket?: (url: string) => WebSocketLike;
  policy?: ReconnectPolicy;
  /** Heartbeat interval (default 10 s, like the native client). */
  pingIntervalMs?: number;
  /** No pong for this long → treat as connection loss (default 25 s). */
  pongTimeoutMs?: number;
  /** Safety net: an unanswered action unlocks after this time (default 6 s). */
  actionTimeoutMs?: number;
  /** Max time from opening the socket to `welcome` (default 20 s; free hosts may cold-start). */
  connectTimeoutMs?: number;
  now?: () => number;
  makeID?: () => string;
}

type Timer = ReturnType<typeof setTimeout>;

/** Mirrors the server's `AccountStore.sanitize(name:)` so we do not rename on every connect. */
export function sanitizeDisplayName(name: string): string {
  // eslint-disable-next-line no-control-regex
  const trimmed = name.trim().replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, '');
  if (!trimmed) return 'Spieler';
  const Seg = (Intl as unknown as { Segmenter?: new (l?: string, o?: { granularity: string }) => { segment(s: string): Iterable<{ segment: string }> } }).Segmenter;
  const parts = Seg ? Array.from(new Seg(undefined, { granularity: 'grapheme' }).segment(trimmed), (s) => s.segment) : Array.from(trimmed);
  return parts.slice(0, 20).join('');
}

export class OnlineService {
  private readonly storage: KeyValueStorage | null;
  private readonly createWebSocket: (url: string) => WebSocketLike;
  private readonly policy: ReconnectPolicy;
  private readonly pingIntervalMs: number;
  private readonly pongTimeoutMs: number;
  private readonly actionTimeoutMs: number;
  private readonly connectTimeoutMs: number;
  private readonly now: () => number;
  private readonly gate: ActionGate;

  // Observable state (mutable internally, published as an immutable snapshot)
  private connection: ConnectionStatus = 'offline';
  private reconnectAttempt = 0;
  private failure: string | null = null;
  private serverURL: string | null;
  private account: AccountInfo | null = null;
  private friends: FriendInfo[] = [];
  private room: RoomInfo | null = null;
  private matchmaking: MatchmakingStatus = { type: 'idle' };
  private table: TableSnapshot | null = null;
  private invitations: Invitation[] = [];
  private tableClosedReason: string | null = null;
  private latencyMs: number | null = null;
  private _state: OnlineState;

  // Connection internals
  private socket: WebSocketLike | null = null;
  private generation = 0;
  private wantsConnection = false;
  private displayName = 'Spieler';
  private lastPong = 0;
  private pingSentAt: number | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private connectTimer: Timer | null = null;
  private reconnectTimer: Timer | null = null;
  private actionTimers = new Set<Timer>();
  private listeners = new Set<(state: OnlineState) => void>();
  private eventListeners = new Set<(event: OnlineEvent) => void>();
  private connectivity: ConnectivityMonitor | null = null;
  private unbindConnectivity: (() => void) | null = null;

  constructor(options: OnlineServiceOptions = {}) {
    this.storage = options.storage !== undefined ? options.storage : defaultStorage();
    this.serverURL = options.serverURL !== undefined ? normalizeServerURL(options.serverURL) : getServerURL(this.storage);
    this.createWebSocket = options.createWebSocket ?? ((url) => new WebSocket(url) as unknown as WebSocketLike);
    this.policy = options.policy ?? new ReconnectPolicy();
    this.pingIntervalMs = options.pingIntervalMs ?? 10_000;
    this.pongTimeoutMs = options.pongTimeoutMs ?? 25_000;
    this.actionTimeoutMs = options.actionTimeoutMs ?? 6_000;
    this.connectTimeoutMs = options.connectTimeoutMs ?? 20_000;
    this.now = options.now ?? Date.now;
    this.gate = new ActionGate(options.makeID ?? makeUUID);
    this._state = this.buildState();
  }

  // MARK: - Observation

  get state(): OnlineState { return this._state; }
  get isConnected(): boolean { return this.connection === 'online'; }
  get isAtTable(): boolean { return this.table !== null; }
  get isServerConfigured(): boolean { return this.serverURL !== null; }
  get canAct(): boolean { return this._state.canAct; }

  /** Listener is called with the new state after every change. Returns an unsubscribe function. */
  subscribe(listener: (state: OnlineState) => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  /** Transient events (notices, errors, invitations, action results). Returns an unsubscribe function. */
  subscribeEvents(listener: (event: OnlineEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => { this.eventListeners.delete(listener); };
  }

  private buildState(): OnlineState {
    return Object.freeze({
      connection: this.connection,
      reconnectAttempt: this.connection === 'reconnecting' ? this.reconnectAttempt : 0,
      failure: this.failure,
      serverURL: this.serverURL,
      account: this.account,
      friends: this.friends,
      room: this.room,
      matchmaking: this.matchmaking,
      table: this.table,
      invitations: this.invitations,
      tableClosedReason: this.tableClosedReason,
      pendingActionID: this.gate.pendingActionID,
      canAct: this.connection === 'online' && !this.gate.isBusy,
      latencyMs: this.latencyMs,
    });
  }

  private emit(): void {
    const next = this.buildState();
    const prev = this._state;
    if ((Object.keys(next) as (keyof OnlineState)[]).every((k) => prev[k] === next[k])) return;
    this._state = next;
    for (const l of [...this.listeners]) {
      try { l(next); } catch (e) { console.error('[OnlineService] listener failed', e); }
    }
  }

  private fire(event: OnlineEvent): void {
    for (const l of [...this.eventListeners]) {
      try { l(event); } catch (e) { console.error('[OnlineService] event listener failed', e); }
    }
  }

  // MARK: - Configuration & identity

  /**
   * Changes the server address and persists it as the localStorage override
   * (`null` = remove override → build-time default, `''` = no server). Reconnects if connected.
   */
  setServerURL(input: string | null, persist = true): void {
    if (persist) setServerURLOverride(input, this.storage);
    this.serverURL = input === null ? getServerURL(this.storage) : normalizeServerURL(input);
    this.failure = null;
    if (this.wantsConnection) this.reconnectNow();
    else this.emit();
  }

  /** True if a token from an earlier registration is stored. */
  get hasStoredIdentity(): boolean { return !!safeGet(this.storage, TOKEN_STORAGE_KEY); }

  /** Forgets the stored token (the next hello registers a new account). Disconnects first. */
  forgetIdentity(): void {
    this.disconnect();
    safeSet(this.storage, TOKEN_STORAGE_KEY, null);
    this.account = null;
    this.friends = [];
    this.invitations = [];
    this.emit();
  }

  // MARK: - Connection

  /** Opens the connection (idempotent). Without a configured server the service stays offline. */
  connect(displayName: string): void {
    this.displayName = displayName;
    this.wantsConnection = true;
    if (this.connection !== 'offline') return; // connecting, online or reconnecting already
    this.open(null);
  }

  /** Deliberate disconnect (page hidden, user left online mode). The server keeps the seat for a grace period. */
  disconnect(): void {
    this.wantsConnection = false;
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'going away');
    this.gate.reset();
    this.connection = 'offline';
    this.failure = null;
    this.emit();
  }

  /** Network is gone: keep state (display only), block actions, reconnect later. */
  networkLost(): void {
    if (!this.wantsConnection) return;
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'network lost');
    this.gate.reset();
    if (this.table || this.room) {
      this.connection = 'reconnecting';
      this.reconnectAttempt = 0;
    } else {
      this.connection = 'offline';
    }
    this.emit();
  }

  networkRestored(): void {
    if (!this.wantsConnection || this.connection === 'online') return;
    if (this.reconnectTimer !== null) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
    this.open(0);
  }

  /** Wires the browser connectivity monitor: offline → `networkLost`, back online → `networkRestored`. */
  bindConnectivity(monitor: ConnectivityMonitor): () => void {
    this.unbindConnectivity?.();
    this.connectivity = monitor;
    let wasOnline = monitor.state.browserOnline;
    const unsub = monitor.subscribe((s) => {
      if (s.browserOnline === wasOnline) return;
      wasOnline = s.browserOnline;
      if (s.browserOnline) this.networkRestored();
      else this.networkLost();
    });
    this.unbindConnectivity = () => {
      unsub();
      if (this.connectivity === monitor) this.connectivity = null;
      this.unbindConnectivity = null;
    };
    return this.unbindConnectivity;
  }

  /** After a final connection failure: leave the local online views. */
  acknowledgeFailure(): void {
    this.table = null;
    this.room = null;
    this.matchmaking = { type: 'idle' };
    this.connection = 'offline';
    this.failure = null;
    this.wantsConnection = false;
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'acknowledged');
    this.emit();
  }

  /** Stops everything and removes all listeners. */
  dispose(): void {
    this.disconnect();
    for (const t of this.actionTimers) clearTimeout(t);
    this.actionTimers.clear();
    this.unbindConnectivity?.();
    this.listeners.clear();
    this.eventListeners.clear();
  }

  private reconnectNow(): void {
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'reconnect');
    this.gate.reset();
    this.connection = 'offline';
    this.open(null);
  }

  private open(attempt: number | null): void {
    const url = this.serverURL;
    if (url === null) {
      // No server configured: offline-only, no error.
      this.connection = 'offline';
      this.emit();
      return;
    }
    if (isBlockedMixedContent(url)) {
      this.giveUp('Unsichere Serveradresse (ws://) auf einer https-Seite – bitte wss:// verwenden.');
      return;
    }
    this.generation++;
    const myGeneration = this.generation;
    this.connection = attempt === null ? 'connecting' : 'reconnecting';
    this.reconnectAttempt = attempt ?? 0;
    this.failure = null;
    let ws: WebSocketLike;
    try {
      ws = this.createWebSocket(url);
    } catch {
      this.giveUp('Ungültige Serveradresse.');
      return;
    }
    this.socket = ws;
    const previousAttempt = attempt ?? 0;
    ws.onopen = () => {
      if (myGeneration !== this.generation) return;
      this.sendRaw({
        type: 'hello',
        hello: { token: safeGet(this.storage, TOKEN_STORAGE_KEY), displayName: this.displayName, protocolVersion: PROTOCOL_VERSION },
      });
    };
    ws.onmessage = (ev: MessageEvent) => {
      if (myGeneration !== this.generation) return;
      if (typeof ev.data !== 'string') return; // server only sends text frames
      const message = decodeServerMessage(ev.data);
      if (!message) return; // malformed: ignore (like the native client)
      try {
        this.handle(message);
      } catch (e) {
        console.error('[OnlineService] failed to handle message', e);
      }
    };
    ws.onclose = () => {
      if (myGeneration !== this.generation) return;
      this.connectionDropped(previousAttempt);
    };
    ws.onerror = () => { /* a close event follows */ };
    this.clearConnectTimer();
    this.connectTimer = setTimeout(() => {
      this.connectTimer = null;
      if (myGeneration !== this.generation || this.connection === 'online') return;
      this.connectionDropped(previousAttempt);
    }, this.connectTimeoutMs);
    this.emit();
  }

  /**
   * Connection dropped: game state stays (display only), actions are blocked, reconnect with
   * growing pauses. No results are invented.
   */
  private connectionDropped(previousAttempt: number): void {
    const wasOnline = this.connection === 'online';
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'dropped');
    this.gate.reset();
    if (!this.wantsConnection) {
      this.connection = 'offline';
      this.emit();
      return;
    }
    const attempt = wasOnline ? 0 : previousAttempt + 1;
    const delay = this.policy.delayMs(attempt);
    if (delay === null) {
      this.matchmaking = { type: 'idle' };
      this.connectivity?.reportServerReachable(false);
      this.giveUp('Verbindung konnte nicht wiederhergestellt werden.');
      return;
    }
    this.connection = 'reconnecting';
    this.reconnectAttempt = attempt;
    const myGeneration = this.generation;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (myGeneration !== this.generation || !this.wantsConnection) return;
      this.open(attempt);
    }, delay);
    this.emit();
  }

  private giveUp(reason: string): void {
    this.generation++;
    this.stopTimers();
    this.abandonSocket(1000, 'failed');
    this.gate.reset();
    this.connection = 'offline';
    this.failure = reason;
    this.emit();
  }

  private abandonSocket(code: number, reason: string): void {
    const ws = this.socket;
    this.socket = null;
    if (!ws) return;
    ws.onopen = null;
    ws.onmessage = null;
    ws.onclose = null;
    ws.onerror = null;
    try { ws.close(code, reason); } catch { /* already closed */ }
  }

  private clearConnectTimer(): void {
    if (this.connectTimer !== null) clearTimeout(this.connectTimer);
    this.connectTimer = null;
  }

  private stopTimers(): void {
    this.clearConnectTimer();
    if (this.reconnectTimer !== null) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = null;
    if (this.pingTimer !== null) clearInterval(this.pingTimer);
    this.pingTimer = null;
    this.pingSentAt = null;
  }

  private startHeartbeat(): void {
    if (this.pingTimer !== null) clearInterval(this.pingTimer);
    this.lastPong = this.now();
    const myGeneration = this.generation;
    this.ping(); // initial latency measurement
    this.pingTimer = setInterval(() => {
      if (myGeneration !== this.generation) return;
      if (this.now() - this.lastPong > this.pongTimeoutMs) {
        // No answer any more: treat like a connection drop
        this.connectionDropped(0);
        return;
      }
      this.ping();
    }, this.pingIntervalMs);
  }

  /** Sends a ping; the round-trip time is published as `state.latencyMs` when the pong arrives. */
  ping(): boolean {
    if (!this.sendRaw({ type: 'ping' })) return false;
    this.pingSentAt = this.now();
    return true;
  }

  private sendRaw(message: ClientMessage): boolean {
    const ws = this.socket;
    if (!ws || ws.readyState !== WS_OPEN) return false;
    try {
      ws.send(encodeClientMessage(message));
      return true;
    } catch {
      return false;
    }
  }

  /** Sends only when welcomed (the server rejects everything but hello/ping before that). */
  private send(message: ClientMessage): boolean {
    return this.connection === 'online' && this.sendRaw(message);
  }

  // MARK: - Incoming messages

  private handle(message: ServerMessage): void {
    switch (message.type) {
      case 'welcome': {
        const info = message.account;
        if (info.token) safeSet(this.storage, TOKEN_STORAGE_KEY, info.token);
        this.account = info;
        this.connection = 'online';
        this.reconnectAttempt = 0;
        this.failure = null;
        this.clearConnectTimer();
        this.startHeartbeat();
        this.connectivity?.reportServerReachable(true);
        const wanted = sanitizeDisplayName(this.displayName);
        if (info.player.displayName !== wanted) this.send({ type: 'rename', displayName: this.displayName });
        break;
      }
      case 'account':
        this.account = message.account;
        break;
      case 'friends':
        this.friends = message.friends;
        break;
      case 'room':
        this.room = message.room;
        break;
      case 'invitation': {
        const inv = message.invitation;
        this.invitations = [...this.invitations.filter((i) => i.roomCode !== inv.roomCode), inv];
        this.fire({ type: 'invitation', invitation: inv });
        break;
      }
      case 'matchmaking':
        this.matchmaking = message.status;
        if (message.status.type === 'noMatchFound') this.fire({ type: 'botOffer', game: message.status.game });
        break;
      case 'table': {
        const snapshot = message.snapshot;
        // Only accept newer states – never jump back
        const current = this.table;
        if (current && current.tableID === snapshot.tableID && snapshot.version < current.version) return;
        this.table = snapshot;
        this.tableClosedReason = null;
        break;
      }
      case 'tableClosed':
        this.table = null;
        this.tableClosedReason = message.reason;
        this.gate.reset();
        if (this.matchmaking.type === 'matched') this.matchmaking = { type: 'idle' };
        this.fire({ type: 'tableClosed', reason: message.reason });
        break;
      case 'actionResult': {
        const result = message.result;
        this.gate.resolve(result.actionID);
        this.fire({ type: 'actionResult', result });
        if (!result.accepted && result.reason) this.fire({ type: 'notice', text: result.reason, isError: true });
        break;
      }
      case 'notice':
        this.fire({ type: 'notice', text: message.text, isError: false });
        break;
      case 'error':
        this.gate.reset();
        this.fire({ type: 'error', error: message.error });
        this.fire({ type: 'notice', text: message.error.message, isError: true });
        if (message.error.code === 'protocolMismatch') {
          // Retrying cannot help: the app must be updated.
          this.wantsConnection = false;
          this.giveUp(message.error.message);
          return;
        }
        if (message.error.code === 'notAuthenticated' && this.connection === 'online') {
          // The server bound this account to a newer connection (another tab/device with the same
          // token). It does not close the old socket, so stop here instead of fighting over the session.
          this.wantsConnection = false;
          this.giveUp(SESSION_TAKEN_OVER_TEXT);
          return;
        }
        break;
      case 'pong': {
        const t = this.now();
        this.lastPong = t;
        if (this.pingSentAt !== null) {
          this.latencyMs = Math.max(0, t - this.pingSentAt);
          this.pingSentAt = null;
        }
        break;
      }
    }
    this.emit();
  }

  // MARK: - Actions (intents only). Each returns whether the message was sent.

  rename(name: string): boolean {
    this.displayName = name;
    return this.send({ type: 'rename', displayName: name });
  }

  addFriend(code: string): boolean {
    return this.send({ type: 'addFriend', friendCode: code.trim().toUpperCase() });
  }

  removeFriend(playerID: string): boolean { return this.send({ type: 'removeFriend', playerID }); }
  createRoom(game: OnlineGame): boolean { return this.send({ type: 'createRoom', game }); }
  setRoomGame(game: OnlineGame): boolean { return this.send({ type: 'setRoomGame', game }); }
  /** Host only; the server answers `notHost` / `notEnoughPlayers` errors otherwise. */
  startRoom(): boolean { return this.send({ type: 'startRoom' }); }
  invite(friendID: string): boolean { return this.send({ type: 'inviteFriend', playerID: friendID }); }
  claimRescue(): boolean { return this.send({ type: 'claimOnlineRescue' }); }

  leaveRoom(): void {
    this.send({ type: 'leaveRoom' });
    this.room = null;
    this.emit();
  }

  /** Joins a room by code. Returns `false` only if the code is invalid (input normalized like the server). */
  joinRoom(code: string): boolean {
    const normalized = RoomCode.normalize(code);
    if (normalized === null) return false;
    this.send({ type: 'joinRoom', code: normalized });
    return true;
  }

  accept(invitation: Invitation): boolean {
    const id = invitationID(invitation);
    this.invitations = this.invitations.filter((i) => invitationID(i) !== id);
    const sent = this.send({ type: 'joinRoom', code: invitation.roomCode });
    this.emit();
    return sent;
  }

  decline(invitation: Invitation): void {
    const id = invitationID(invitation);
    this.invitations = this.invitations.filter((i) => invitationID(i) !== id);
    this.emit();
  }

  /** Random matchmaking. After a while the server may answer `noMatchFound` → offer bots. */
  findMatch(game: OnlineGame): boolean {
    if (!this.send({ type: 'findMatch', game })) return false;
    this.matchmaking = { type: 'searching', game, since: this.now() };
    this.emit();
    return true;
  }

  /** Answer to the bot offer: play with bots now. */
  playWithBots(): boolean { return this.send({ type: 'matchWithBots' }); }
  /** Answer to the bot offer: keep waiting for real players. */
  keepWaiting(): boolean { return this.send({ type: 'keepWaiting' }); }

  cancelMatch(): void {
    this.send({ type: 'cancelMatch' });
    this.matchmaking = { type: 'idle' };
    this.emit();
  }

  leaveTable(): void {
    this.send({ type: 'leaveTable' });
    this.table = null;
    this.gate.reset();
    this.matchmaking = { type: 'idle' };
    this.emit();
  }

  /**
   * Sends a table action with the current `stateVersion` and a fresh action id.
   * Returns `false` if no action is possible right now (pending action, not connected, no table)
   * – this prevents double taps.
   */
  act(action: TableAction): boolean {
    const table = this.table;
    if (this.connection !== 'online' || !table) return false;
    const id = this.gate.begin(this.now());
    if (id === null) return false;
    if (!this.send({ type: 'tableAction', request: { actionID: id, stateVersion: table.version, action } })) {
      this.gate.reset();
      return false;
    }
    // Safety net: without an answer the gate unlocks after a few seconds
    const timer = setTimeout(() => {
      this.actionTimers.delete(timer);
      this.gate.resolve(id);
      this.emit();
    }, this.actionTimeoutMs);
    this.actionTimers.add(timer);
    this.emit();
    return true;
  }

  clearClosedReason(): void {
    this.tableClosedReason = null;
    this.emit();
  }
}
