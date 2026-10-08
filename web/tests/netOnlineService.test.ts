import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ConnectivityMonitor } from '../src/net/connectivity';
import type { KeyValueStorage } from '../src/net/config';
import {
  BOT_OFFER_TEXT, OnlineService, SESSION_TAKEN_OVER_TEXT, TOKEN_STORAGE_KEY, sanitizeDisplayName, type OnlineEvent, type OnlineState, type WebSocketLike,
} from '../src/net/onlineService';
import {
  decodeClientMessage, encodeServerMessage, type ClientMessage, type PlayerInfo, type ServerMessage, type TableSnapshot,
} from '../src/net/protocol';

class MemoryStorage implements KeyValueStorage {
  map = new Map<string, string>();
  getItem(k: string) { return this.map.get(k) ?? null; }
  setItem(k: string, v: string) { this.map.set(k, v); }
  removeItem(k: string) { this.map.delete(k); }
}

class FakeWebSocket implements WebSocketLike {
  readyState = 0;
  sentRaw: string[] = [];
  closed: { code?: number; reason?: string } | null = null;
  onopen: ((ev: Event) => unknown) | null = null;
  onmessage: ((ev: MessageEvent) => unknown) | null = null;
  onclose: ((ev: CloseEvent) => unknown) | null = null;
  onerror: ((ev: Event) => unknown) | null = null;

  constructor(readonly url: string) {}

  send(data: string) {
    if (this.readyState !== 1) throw new Error('not open');
    this.sentRaw.push(data);
  }
  close(code?: number, reason?: string) {
    this.closed = { code, reason };
    this.readyState = 3;
  }
  get sent(): ClientMessage[] {
    return this.sentRaw.map((s) => {
      const m = decodeClientMessage(s);
      if (!m) throw new Error(`client sent malformed message ${s}`);
      return m;
    });
  }
  sentTypes(): string[] { return this.sent.map((m) => m.type); }
  // server side helpers
  open() { this.readyState = 1; this.onopen?.(new Event('open')); }
  receive(m: ServerMessage) { this.onmessage?.({ data: encodeServerMessage(m) } as MessageEvent); }
  receiveRaw(data: unknown) { this.onmessage?.({ data } as MessageEvent); }
  drop() { this.readyState = 3; this.onclose?.({ code: 1006 } as CloseEvent); }
}

const me: PlayerInfo = { id: 'P1', displayName: 'Kim', friendCode: 'ABC234' };
const lea: PlayerInfo = { id: 'P2', displayName: 'Lea', friendCode: 'XYZ789' };

function welcome(token: string | null = 'tok-1', player: PlayerInfo = me): ServerMessage {
  return { type: 'welcome', account: { player, onlineChips: 10000, token } };
}

function snapshot(version: number, tableID = 'T1'): TableSnapshot {
  return {
    tableID, game: 'poker', version, isPrivate: false, yourSeatID: 0,
    seats: [{ seatID: 0, player: me, isBot: false, botStyle: null, isConnected: true }],
    turnDeadline: null, blackjack: null, poker: null,
  };
}

function setup(opts: { serverURL?: string | null; storage?: MemoryStorage } = {}) {
  const sockets: FakeWebSocket[] = [];
  const storage = opts.storage ?? new MemoryStorage();
  let n = 0;
  const service = new OnlineService({
    serverURL: opts.serverURL === undefined ? 'wss://casino.example/ws' : opts.serverURL,
    storage,
    createWebSocket: (url) => { const ws = new FakeWebSocket(url); sockets.push(ws); return ws; },
    makeID: () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`,
  });
  const states: OnlineState[] = [];
  const events: OnlineEvent[] = [];
  service.subscribe((s) => states.push(s));
  service.subscribeEvents((e) => events.push(e));
  const last = () => sockets[sockets.length - 1]!;
  const connectOnline = (token: string | null = 'tok-1') => {
    service.connect('Kim');
    last().open();
    last().receive(welcome(token));
    return last();
  };
  return { service, sockets, storage, states, events, last, connectOnline };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-08T12:00:00Z'));
});

afterEach(() => {
  vi.useRealTimers();
});

describe('OnlineService: connection', () => {
  it('stays offline without a configured server', () => {
    const { service, sockets } = setup({ serverURL: null });
    service.connect('Kim');
    expect(sockets).toHaveLength(0);
    expect(service.state.connection).toBe('offline');
    expect(service.state.failure).toBeNull();
    expect(service.isServerConfigured).toBe(false);
  });

  it('runs the hello/welcome handshake and stores the token', () => {
    const { service, last, storage } = setup();
    service.connect('Kim');
    expect(service.state.connection).toBe('connecting');
    expect(last().url).toBe('wss://casino.example/ws');
    last().open();
    expect(last().sent).toEqual([{ type: 'hello', hello: { token: null, displayName: 'Kim', protocolVersion: 1 } }]);
    expect(last().sentRaw[0]).toBe('{"hello":{"_0":{"displayName":"Kim","protocolVersion":1}}}');
    last().receive(welcome('tok-1'));
    expect(service.state.connection).toBe('online');
    expect(service.state.account?.onlineChips).toBe(10000);
    expect(storage.getItem(TOKEN_STORAGE_KEY)).toBe('tok-1');
    expect(service.hasStoredIdentity).toBe(true);
    // initial latency ping, no rename since the name matches
    expect(last().sentTypes()).toEqual(['hello', 'ping']);
  });

  it('sends a stored token and renames when the server name differs', () => {
    const storage = new MemoryStorage();
    storage.setItem(TOKEN_STORAGE_KEY, 'saved');
    const { service, last } = setup({ storage });
    service.connect('Neuer Name');
    last().open();
    expect(last().sent[0]).toEqual({ type: 'hello', hello: { token: 'saved', displayName: 'Neuer Name', protocolVersion: 1 } });
    last().receive(welcome(null));
    expect(storage.getItem(TOKEN_STORAGE_KEY)).toBe('saved');
    expect(last().sent).toContainEqual({ type: 'rename', displayName: 'Neuer Name' });
  });

  it('measures latency with ping/pong', () => {
    const { service, last, connectOnline } = setup();
    connectOnline();
    vi.advanceTimersByTime(42);
    last().receive({ type: 'pong' });
    expect(service.state.latencyMs).toBe(42);
    vi.advanceTimersByTime(10_000 - 42);
    expect(last().sentTypes().filter((t) => t === 'ping')).toHaveLength(2);
  });

  it('drops after a missing pong and reconnects', () => {
    const { service, sockets, connectOnline } = setup();
    connectOnline();
    vi.advanceTimersByTime(30_000);
    expect(service.state.connection).toBe('reconnecting');
    expect(service.state.reconnectAttempt).toBe(0);
    expect(sockets[0]!.closed).not.toBeNull();
    vi.advanceTimersByTime(500);
    expect(sockets).toHaveLength(2);
  });

  it('reconnects with the Swift backoff, keeps table state, and gives up after ~60 s', () => {
    const { service, sockets, last, connectOnline, events } = setup();
    connectOnline();
    last().receive({ type: 'table', snapshot: snapshot(3) });
    last().drop();
    expect(service.state.connection).toBe('reconnecting');
    expect(service.state.reconnectAttempt).toBe(0);
    expect(service.state.table?.version).toBe(3); // display only, nothing invented
    expect(service.state.canAct).toBe(false);
    expect(service.act({ type: 'rebuy' })).toBe(false);

    vi.advanceTimersByTime(499);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(2);
    // second attempt fails → attempt 1 (1 s)
    last().drop();
    expect(service.state.reconnectAttempt).toBe(1);
    const expected = [1000, 2000, 4000, 8000, 15000, 15000, 15000];
    for (let i = 0; i < expected.length; i++) {
      const before = sockets.length;
      vi.advanceTimersByTime(expected[i]!);
      expect(sockets.length).toBe(before + 1);
      if (i < expected.length - 1) {
        last().drop();
        expect(service.state.reconnectAttempt).toBe(i + 2);
      }
    }
    last().drop(); // attempt 8 → exhausted
    expect(service.state.connection).toBe('offline');
    expect(service.state.failure).toBe('Verbindung konnte nicht wiederhergestellt werden.');
    expect(service.state.table).not.toBeNull();
    expect(events).toEqual([]);
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(9);

    service.acknowledgeFailure();
    expect(service.state.table).toBeNull();
    expect(service.state.failure).toBeNull();
  });

  it('resumes after a successful reconnect (server re-sends room/table)', () => {
    const { service, last, connectOnline } = setup();
    connectOnline();
    last().drop();
    vi.advanceTimersByTime(500);
    last().open();
    expect(last().sent[0]).toMatchObject({ type: 'hello', hello: { token: 'tok-1' } });
    last().receive(welcome(null));
    expect(service.state.connection).toBe('online');
    expect(service.state.reconnectAttempt).toBe(0);
  });

  it('times out a connection that never gets a welcome', () => {
    const { service, sockets } = setup();
    service.connect('Kim');
    vi.advanceTimersByTime(20_000);
    expect(service.state.connection).toBe('reconnecting');
    expect(service.state.reconnectAttempt).toBe(1);
    vi.advanceTimersByTime(1000);
    expect(sockets).toHaveLength(2);
  });

  it('stops on protocol mismatch', () => {
    const { service, sockets, last, events } = setup();
    service.connect('Kim');
    last().open();
    last().receive({ type: 'error', error: { code: 'protocolMismatch', message: 'Bitte aktualisiere die App.' } });
    expect(service.state.connection).toBe('offline');
    expect(service.state.failure).toBe('Bitte aktualisiere die App.');
    expect(events).toContainEqual({ type: 'notice', text: 'Bitte aktualisiere die App.', isError: true });
    vi.advanceTimersByTime(120_000);
    expect(sockets).toHaveLength(1);
  });

  it('stops when the session was taken over by another tab (notAuthenticated while online)', () => {
    const { service, sockets, last, connectOnline } = setup();
    connectOnline();
    last().receive({ type: 'error', error: { code: 'notAuthenticated', message: 'Bitte zuerst anmelden.' } });
    expect(service.state.connection).toBe('offline');
    expect(service.state.failure).toBe(SESSION_TAKEN_OVER_TEXT);
    vi.advanceTimersByTime(120_000);
    expect(sockets).toHaveLength(1);
    service.connect('Kim'); // user explicitly reconnects
    expect(sockets).toHaveLength(2);
  });

  it('disconnect is deliberate: no reconnect', () => {
    const { service, sockets, connectOnline } = setup();
    const ws = connectOnline();
    service.disconnect();
    expect(ws.closed?.code).toBe(1000);
    expect(service.state.connection).toBe('offline');
    vi.advanceTimersByTime(120_000);
    expect(sockets).toHaveLength(1);
  });

  it('connect is idempotent', () => {
    const { service, sockets, connectOnline } = setup();
    connectOnline();
    service.connect('Kim');
    expect(sockets).toHaveLength(1);
  });

  it('follows browser connectivity (networkLost / networkRestored)', () => {
    const target = new EventTarget();
    let online = true;
    const monitor = new ConnectivityMonitor({ target, documentTarget: null, isOnline: () => online, healthURL: null });
    monitor.start();
    const { service, sockets, last, connectOnline } = setup();
    service.bindConnectivity(monitor);
    connectOnline();
    last().receive({ type: 'room', room: { code: 'ABCDEF', game: 'poker', hostID: 'P1', members: [me], status: 'waiting' } });
    online = false;
    target.dispatchEvent(new Event('offline'));
    expect(service.state.connection).toBe('reconnecting');
    expect(service.state.room?.code).toBe('ABCDEF');
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(1); // waits for the network
    online = true;
    target.dispatchEvent(new Event('online'));
    expect(sockets).toHaveLength(2);
    last().open();
    last().receive(welcome(null));
    expect(service.state.connection).toBe('online');
  });

  it('switching the server URL reconnects and persists the override', () => {
    const { service, sockets, storage, connectOnline } = setup();
    connectOnline();
    service.setServerURL('https://other.example');
    expect(storage.getItem('blackcasino.serverURL')).toBe('https://other.example');
    expect(sockets).toHaveLength(2);
    expect(sockets[1]!.url).toBe('wss://other.example/ws');
    expect(service.state.connection).toBe('connecting');
    service.setServerURL('');
    expect(service.state.connection).toBe('offline');
    expect(service.state.serverURL).toBeNull();
  });

  it('refuses ws:// on an https page (mixed content)', () => {
    vi.stubGlobal('location', { protocol: 'https:' });
    try {
      const { service, sockets } = setup({ serverURL: 'ws://example.com/ws' });
      service.connect('Kim');
      expect(sockets).toHaveLength(0);
      expect(service.state.failure).toMatch(/wss:\/\//);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('ignores malformed and binary messages without throwing', () => {
    const { service, last, connectOnline } = setup();
    connectOnline();
    expect(() => {
      last().receiveRaw('garbage');
      last().receiveRaw('{"table":{"_0":{}}}');
      last().receiveRaw(new ArrayBuffer(2));
    }).not.toThrow();
    expect(service.state.connection).toBe('online');
  });

  it('isolates listener errors and supports unsubscribe', () => {
    const { service, connectOnline } = setup();
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    service.subscribe(() => { throw new Error('ui bug'); });
    const seen: string[] = [];
    const unsub = service.subscribe((s) => seen.push(s.connection));
    connectOnline();
    expect(seen).toContain('online');
    unsub();
    service.disconnect();
    expect(seen).not.toContain('offline');
    errSpy.mockRestore();
  });

  it('sanitizes display names like the server', () => {
    expect(sanitizeDisplayName('  Kim  ')).toBe('Kim');
    expect(sanitizeDisplayName('   ')).toBe('Spieler');
    expect(sanitizeDisplayName('A'.repeat(30))).toBe('A'.repeat(20));
    expect(sanitizeDisplayName('Ki\u0007m')).toBe('Kim');
  });
});

describe('OnlineService: friends, rooms, invitations', () => {
  it('does not send before welcome', () => {
    const { service, last } = setup();
    service.connect('Kim');
    last().open();
    expect(service.createRoom('poker')).toBe(false);
    expect(last().sentTypes()).toEqual(['hello']);
  });

  it('sends room and friend intents in wire format and applies server state', () => {
    const { service, last, connectOnline } = setup();
    const ws = connectOnline();
    expect(service.addFriend(' xyz789 ')).toBe(true);
    expect(service.removeFriend('P2')).toBe(true);
    expect(service.createRoom('blackjack')).toBe(true);
    expect(service.setRoomGame('poker')).toBe(true);
    expect(service.invite('P2')).toBe(true);
    expect(service.startRoom()).toBe(true);
    expect(service.claimRescue()).toBe(true);
    expect(ws.sentRaw.slice(2)).toEqual([
      '{"addFriend":{"friendCode":"XYZ789"}}',
      '{"removeFriend":{"playerID":"P2"}}',
      '{"createRoom":{"game":"blackjack"}}',
      '{"setRoomGame":{"game":"poker"}}',
      '{"inviteFriend":{"playerID":"P2"}}',
      '{"startRoom":{}}',
      '{"claimOnlineRescue":{}}',
    ]);

    last().receive({ type: 'friends', friends: [{ player: lea, presence: 'inGame' }] });
    expect(service.state.friends[0]?.presence).toBe('inGame');
    last().receive({ type: 'room', room: { code: 'K7MP2Q', game: 'poker', hostID: 'P1', members: [me, lea], status: 'waiting' } });
    expect(service.state.room?.members).toHaveLength(2);
    service.leaveRoom();
    expect(ws.sentRaw.at(-1)).toBe('{"leaveRoom":{}}');
    expect(service.state.room).toBeNull();
  });

  it('joins rooms by normalized code and rejects invalid codes', () => {
    const { service, connectOnline } = setup();
    const ws = connectOnline();
    expect(service.joinRoom('abc-0ef')).toBe(false);
    expect(service.joinRoom('k7m p2q')).toBe(true);
    expect(ws.sentRaw.at(-1)).toBe('{"joinRoom":{"code":"K7MP2Q"}}');
  });

  it('collects invitations (deduplicated per room) and accepts/declines them', () => {
    const { service, events, last, connectOnline } = setup();
    const ws = connectOnline();
    const inv = { roomCode: 'K7MP2Q', game: 'poker' as const, from: lea };
    last().receive({ type: 'invitation', invitation: inv });
    last().receive({ type: 'invitation', invitation: inv });
    expect(service.state.invitations).toHaveLength(1);
    expect(events.filter((e) => e.type === 'invitation')).toHaveLength(2);
    service.accept(inv);
    expect(service.state.invitations).toHaveLength(0);
    expect(ws.sentRaw.at(-1)).toBe('{"joinRoom":{"code":"K7MP2Q"}}');
    last().receive({ type: 'invitation', invitation: { ...inv, roomCode: 'ABCDEF' } });
    service.decline(service.state.invitations[0]!);
    expect(service.state.invitations).toHaveLength(0);
  });

  it('forwards notices and errors as events', () => {
    const { events, last, connectOnline } = setup();
    connectOnline();
    last().receive({ type: 'notice', text: 'Einladung gesendet.' });
    last().receive({ type: 'error', error: { code: 'roomNotFound', message: 'Kein Raum mit diesem Code gefunden.' } });
    expect(events).toEqual([
      { type: 'notice', text: 'Einladung gesendet.', isError: false },
      { type: 'error', error: { code: 'roomNotFound', message: 'Kein Raum mit diesem Code gefunden.' } },
      { type: 'notice', text: 'Kein Raum mit diesem Code gefunden.', isError: true },
    ]);
  });
});

describe('OnlineService: random matchmaking', () => {
  it('search → no match → bot offer → play with bots', () => {
    const { service, events, last, connectOnline } = setup();
    const ws = connectOnline();
    expect(service.findMatch('poker')).toBe(true);
    expect(ws.sentRaw.at(-1)).toBe('{"findMatch":{"game":"poker"}}');
    expect(service.state.matchmaking).toEqual({ type: 'searching', game: 'poker', since: Date.now() });
    last().receive({ type: 'matchmaking', status: { type: 'searching', game: 'poker', since: 1700000000000 } });
    last().receive({ type: 'matchmaking', status: { type: 'noMatchFound', game: 'poker' } });
    expect(service.state.matchmaking.type).toBe('noMatchFound');
    expect(events).toContainEqual({ type: 'botOffer', game: 'poker' });
    expect(BOT_OFFER_TEXT).toBe('Kein Spieler gefunden. Mit Bots spielen?');
    service.keepWaiting();
    expect(ws.sentRaw.at(-1)).toBe('{"keepWaiting":{}}');
    service.playWithBots();
    expect(ws.sentRaw.at(-1)).toBe('{"matchWithBots":{}}');
    last().receive({ type: 'matchmaking', status: { type: 'matched', tableID: 'T1' } });
    last().receive({ type: 'table', snapshot: snapshot(1) });
    expect(service.isAtTable).toBe(true);
  });

  it('cancel resets to idle', () => {
    const { service, connectOnline } = setup();
    const ws = connectOnline();
    service.findMatch('blackjack');
    service.cancelMatch();
    expect(ws.sentRaw.at(-1)).toBe('{"cancelMatch":{}}');
    expect(service.state.matchmaking).toEqual({ type: 'idle' });
  });

  it('does not pretend to search while offline', () => {
    const { service } = setup();
    expect(service.findMatch('poker')).toBe(false);
    expect(service.state.matchmaking).toEqual({ type: 'idle' });
  });
});

describe('OnlineService: table actions', () => {
  it('sends actions with stateVersion and id, blocks double taps until the result', () => {
    const { service, events, last, connectOnline } = setup();
    const ws = connectOnline();
    last().receive({ type: 'table', snapshot: snapshot(7) });
    expect(service.state.canAct).toBe(true);
    expect(service.act({ type: 'poker', action: { type: 'raise', to: 40 } })).toBe(true);
    const id = '00000000-0000-4000-8000-000000000001';
    expect(ws.sentRaw.at(-1)).toBe(
      `{"tableAction":{"_0":{"actionID":"${id}","stateVersion":7,"action":{"poker":{"action":{"raise":{"to":40}}}}}}}`,
    );
    expect(service.state.pendingActionID).toBe(id);
    expect(service.state.canAct).toBe(false);
    expect(service.act({ type: 'poker', action: { type: 'fold' } })).toBe(false);

    last().receive({ type: 'actionResult', result: { actionID: id, accepted: false, reason: 'Spielstand veraltet – bitte erneut versuchen.' } });
    expect(service.state.canAct).toBe(true);
    expect(events).toContainEqual({ type: 'notice', text: 'Spielstand veraltet – bitte erneut versuchen.', isError: true });

    expect(service.act({ type: 'placeBet', amount: 50 })).toBe(true);
    expect(service.state.canAct).toBe(false);
    vi.advanceTimersByTime(6000); // safety net
    expect(service.state.canAct).toBe(true);
  });

  it('never jumps back to older snapshots of the same table', () => {
    const { service, last, connectOnline } = setup();
    connectOnline();
    last().receive({ type: 'table', snapshot: snapshot(5) });
    last().receive({ type: 'table', snapshot: snapshot(4) });
    expect(service.state.table?.version).toBe(5);
    last().receive({ type: 'table', snapshot: snapshot(6) });
    expect(service.state.table?.version).toBe(6);
    last().receive({ type: 'table', snapshot: snapshot(1, 'T2') });
    expect(service.state.table?.tableID).toBe('T2');
  });

  it('handles tableClosed and leaveTable', () => {
    const { service, events, last, connectOnline } = setup();
    const ws = connectOnline();
    last().receive({ type: 'table', snapshot: snapshot(1) });
    service.act({ type: 'rebuy' });
    last().receive({ type: 'tableClosed', reason: 'Verbindung verloren' });
    expect(service.state.table).toBeNull();
    expect(service.state.tableClosedReason).toBe('Verbindung verloren');
    expect(service.state.pendingActionID).toBeNull();
    expect(events).toContainEqual({ type: 'tableClosed', reason: 'Verbindung verloren' });
    service.clearClosedReason();
    expect(service.state.tableClosedReason).toBeNull();

    last().receive({ type: 'table', snapshot: snapshot(2) });
    service.leaveTable();
    expect(ws.sentRaw.at(-1)).toBe('{"leaveTable":{}}');
    expect(service.state.table).toBeNull();
    expect(service.state.matchmaking).toEqual({ type: 'idle' });
  });

  it('publishes immutable state snapshots', () => {
    const { service, connectOnline } = setup();
    connectOnline();
    const s1 = service.state;
    expect(Object.isFrozen(s1)).toBe(true);
    service.findMatch('poker');
    expect(service.state).not.toBe(s1);
    expect(s1.matchmaking.type).toBe('idle');
  });
});

describe('ConnectivityMonitor', () => {
  it('combines navigator.onLine, events and the server health probe', async () => {
    const target = new EventTarget();
    let online = true;
    let reachable = false;
    const fetchMock = vi.fn(async () => {
      if (!reachable) throw new TypeError('Failed to fetch');
      return { type: 'opaque' } as Response;
    });
    const monitor = new ConnectivityMonitor({
      target, documentTarget: null, isOnline: () => online, healthURL: 'https://casino.example/health',
      fetch: fetchMock as unknown as typeof fetch, retryIntervalMs: 30_000,
    });
    const statuses: string[] = [];
    monitor.subscribe((s) => statuses.push(s.status));
    monitor.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(fetchMock).toHaveBeenCalledWith('https://casino.example/health', expect.objectContaining({ mode: 'no-cors' }));
    expect(monitor.status).toBe('offline');
    expect(monitor.state.serverReachable).toBe(false);

    reachable = true;
    await vi.advanceTimersByTimeAsync(30_000); // retry
    expect(monitor.status).toBe('online');
    expect(monitor.state.serverReachable).toBe(true);

    online = false;
    target.dispatchEvent(new Event('offline'));
    expect(monitor.status).toBe('offline');
    online = true;
    target.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(0);
    expect(monitor.status).toBe('online');
    expect(statuses).toEqual(['offline', 'online', 'offline', 'online']);
    monitor.stop();
  });

  it('without a server follows the browser only', () => {
    const target = new EventTarget();
    let online = false;
    const monitor = new ConnectivityMonitor({ target, documentTarget: null, isOnline: () => online, healthURL: null });
    monitor.start();
    expect(monitor.status).toBe('offline');
    online = true;
    target.dispatchEvent(new Event('online'));
    expect(monitor.status).toBe('online');
    expect(monitor.state.serverReachable).toBeNull();
  });
});
