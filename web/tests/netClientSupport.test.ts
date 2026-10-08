import { describe, expect, it } from 'vitest';
import { ActionGate, ReconnectPolicy, RoomCode, makeUUID } from '../src/net/clientSupport';
import { getServerURL, healthURLFor, isBlockedMixedContent, normalizeServerURL, setServerURLOverride, type KeyValueStorage } from '../src/net/config';

class MemoryStorage implements KeyValueStorage {
  map = new Map<string, string>();
  getItem(k: string) { return this.map.get(k) ?? null; }
  setItem(k: string, v: string) { this.map.set(k, v); }
  removeItem(k: string) { this.map.delete(k); }
}

describe('RoomCode', () => {
  it('uses the Swift alphabet (no 0/O, 1/I) and length 6', () => {
    expect(RoomCode.alphabet).toBe('ABCDEFGHJKLMNPQRSTUVWXYZ23456789');
    expect(RoomCode.alphabet).toHaveLength(32);
    expect(RoomCode.length).toBe(6);
  });

  it('normalizes user input like Swift', () => {
    expect(RoomCode.normalize('abcdef')).toBe('ABCDEF');
    expect(RoomCode.normalize(' ab-cd ef ')).toBe('ABCDEF');
    expect(RoomCode.normalize('AB\tC-D\nEF')).toBe('ABCDEF');
    expect(RoomCode.normalize('k7m-p2q')).toBe('K7MP2Q');
  });

  it('rejects invalid codes', () => {
    expect(RoomCode.normalize('ABCDE')).toBeNull();
    expect(RoomCode.normalize('ABCDEFG')).toBeNull();
    expect(RoomCode.normalize('ABCDE0')).toBeNull();
    expect(RoomCode.normalize('ABCDEO')).toBeNull();
    expect(RoomCode.normalize('ABCDE1')).toBeNull();
    expect(RoomCode.normalize('ABCDEI')).toBeNull();
    expect(RoomCode.normalize('ABCDÄF')).toBeNull();
    expect(RoomCode.normalize('')).toBeNull();
    expect(RoomCode.isValid('abc def')).toBe(true);
  });

  it('generates valid codes', () => {
    for (let i = 0; i < 200; i++) {
      const code = RoomCode.generate();
      expect(code).toHaveLength(6);
      expect(RoomCode.normalize(code)).toBe(code);
    }
  });
});

describe('makeUUID', () => {
  it('returns uppercase UUIDs (Swift uuidString format)', () => {
    const id = makeUUID();
    expect(id).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/);
    expect(makeUUID()).not.toBe(id);
  });
});

describe('ActionGate', () => {
  it('blocks a second action until resolved', () => {
    let n = 0;
    const gate = new ActionGate(() => `ID-${++n}`);
    expect(gate.isBusy).toBe(false);
    const a = gate.begin(1000);
    expect(a).toBe('ID-1');
    expect(gate.isBusy).toBe(true);
    expect(gate.pendingSince).toBe(1000);
    expect(gate.begin()).toBeNull();
    gate.resolve('ID-other');
    expect(gate.isBusy).toBe(true);
    gate.resolve('ID-1');
    expect(gate.isBusy).toBe(false);
    expect(gate.pendingSince).toBeNull();
    expect(gate.begin()).toBe('ID-2');
    gate.reset();
    expect(gate.pendingActionID).toBeNull();
  });

  it('resolves case-insensitively (server echoes uppercase UUIDs)', () => {
    const gate = new ActionGate(() => 'e621e1f8-c36c-495a-93fc-0c247a3e6e5f');
    gate.begin();
    gate.resolve('E621E1F8-C36C-495A-93FC-0C247A3E6E5F');
    expect(gate.isBusy).toBe(false);
  });
});

describe('ReconnectPolicy', () => {
  it('has the same backoff as Swift', () => {
    const p = new ReconnectPolicy();
    expect(p.delays).toEqual([0.5, 1, 2, 4, 8, 15, 15, 15]);
    expect(p.totalDuration).toBe(60.5);
    expect(p.delay(0)).toBe(0.5);
    expect(p.delay(4)).toBe(8);
    expect(p.delay(7)).toBe(15);
    expect(p.delay(8)).toBeNull();
    expect(p.delay(-1)).toBeNull();
    expect(p.delayMs(0)).toBe(500);
    expect(p.delayMs(8)).toBeNull();
  });

  it('supports custom delays', () => {
    const p = new ReconnectPolicy([1, 2]);
    expect(p.totalDuration).toBe(3);
    expect(p.delay(2)).toBeNull();
  });
});

describe('server URL config', () => {
  it('normalizes addresses', () => {
    expect(normalizeServerURL('wss://casino.example.com/ws')).toBe('wss://casino.example.com/ws');
    expect(normalizeServerURL('https://casino.example.com')).toBe('wss://casino.example.com/ws');
    expect(normalizeServerURL('http://localhost:8080')).toBe('ws://localhost:8080/ws');
    expect(normalizeServerURL('casino.onrender.com')).toBe('wss://casino.onrender.com/ws');
    expect(normalizeServerURL('  ')).toBeNull();
    expect(normalizeServerURL('')).toBeNull();
    expect(normalizeServerURL(undefined)).toBeNull();
    expect(normalizeServerURL('ftp://x')).toBeNull();
  });

  it('derives the health URL', () => {
    expect(healthURLFor('wss://casino.example.com/ws')).toBe('https://casino.example.com/health');
    expect(healthURLFor('ws://localhost:8080/ws')).toBe('http://localhost:8080/health');
  });

  it('detects mixed content', () => {
    expect(isBlockedMixedContent('ws://example.com/ws', 'https:')).toBe(true);
    expect(isBlockedMixedContent('ws://localhost:8080/ws', 'https:')).toBe(false);
    expect(isBlockedMixedContent('wss://example.com/ws', 'https:')).toBe(false);
    expect(isBlockedMixedContent('ws://example.com/ws', 'http:')).toBe(false);
  });

  it('prefers the localStorage override, empty means no server', () => {
    const s = new MemoryStorage();
    expect(getServerURL(s, undefined)).toBeNull();
    expect(getServerURL(s, '')).toBeNull();
    expect(getServerURL(s, 'wss://env.example/ws')).toBe('wss://env.example/ws');
    setServerURLOverride('https://override.example', s);
    expect(s.getItem('blackcasino.serverURL')).toBe('https://override.example');
    expect(getServerURL(s, 'wss://env.example/ws')).toBe('wss://override.example/ws');
    setServerURLOverride('', s);
    expect(getServerURL(s, 'wss://env.example/ws')).toBeNull();
    setServerURLOverride(null, s);
    expect(getServerURL(s, 'wss://env.example/ws')).toBe('wss://env.example/ws');
  });

  it('survives a throwing storage', () => {
    const throwing: KeyValueStorage = {
      getItem() { throw new Error('denied'); },
      setItem() { throw new Error('denied'); },
      removeItem() { throw new Error('denied'); },
    };
    expect(() => setServerURLOverride('x', throwing)).not.toThrow();
    expect(getServerURL(throwing, 'wss://env.example/ws')).toBe('wss://env.example/ws');
  });
});
