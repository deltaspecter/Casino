/**
 * Server URL configuration.
 *
 * Resolution order:
 *  1. localStorage override `blackcasino.serverURL` (set via `setServerURLOverride`, e.g. from a settings screen)
 *  2. build-time `import.meta.env.VITE_SERVER_URL`
 *  3. nothing → `null` = "no server configured": the app stays offline-only.
 *
 * Accepted inputs: `wss://host/ws`, `ws://host:8080/ws`, and for convenience `https://host` / `host`
 * (converted to `wss://host/ws`). An empty string (in either source) means "no server".
 */

export const SERVER_URL_STORAGE_KEY = 'blackcasino.serverURL';

/** Minimal Storage subset (so tests or non-browser hosts can inject their own). */
export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

/** `localStorage` if usable (may throw in private mode / sandboxed iframes), otherwise `null`. */
export function defaultStorage(): KeyValueStorage | null {
  try {
    const s = globalThis.localStorage;
    return s ?? null;
  } catch {
    return null;
  }
}

export function safeGet(storage: KeyValueStorage | null, key: string): string | null {
  try {
    return storage ? storage.getItem(key) : null;
  } catch {
    return null;
  }
}

export function safeSet(storage: KeyValueStorage | null, key: string, value: string | null): void {
  try {
    if (!storage) return;
    if (value === null) storage.removeItem(key);
    else storage.setItem(key, value);
  } catch {
    // quota / private mode – ignore
  }
}

function envServerURL(): string | undefined {
  try {
    const v: unknown = import.meta.env?.VITE_SERVER_URL;
    return typeof v === 'string' ? v : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Normalizes a server address to a WebSocket URL, or returns `null` if it is empty/invalid.
 * `https://x` → `wss://x/ws`, `http://x` → `ws://x/ws`, bare host → `wss://host/ws`.
 * A URL with an explicit path keeps it.
 */
export function normalizeServerURL(input: string | null | undefined): string | null {
  const raw = (input ?? '').trim();
  if (!raw) return null;
  let candidate = raw;
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(candidate)) candidate = `wss://${candidate}`;
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return null;
  }
  if (url.protocol === 'https:') url.protocol = 'wss:';
  else if (url.protocol === 'http:') url.protocol = 'ws:';
  if (url.protocol !== 'wss:' && url.protocol !== 'ws:') return null;
  if (!url.hostname) return null;
  if (url.pathname === '' || url.pathname === '/') url.pathname = '/ws';
  url.hash = '';
  return url.toString();
}

/** HTTP(S) URL of the server's `GET /health` endpoint for a WebSocket URL. */
export function healthURLFor(wsURL: string): string | null {
  try {
    const url = new URL(wsURL);
    url.protocol = url.protocol === 'wss:' ? 'https:' : url.protocol === 'ws:' ? 'http:' : url.protocol;
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    url.pathname = '/health';
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return null;
  }
}

/** True if the browser would block this WebSocket as mixed content (https page → ws:// remote host). */
export function isBlockedMixedContent(wsURL: string, pageProtocol: string | undefined = globalThis.location?.protocol): boolean {
  try {
    const url = new URL(wsURL);
    if (pageProtocol !== 'https:' || url.protocol !== 'ws:') return false;
    return !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  } catch {
    return true;
  }
}

/** Raw override from localStorage (`null` = not set). An empty string disables the server. */
export function getServerURLOverride(storage: KeyValueStorage | null = defaultStorage()): string | null {
  return safeGet(storage, SERVER_URL_STORAGE_KEY);
}

/** Stores an override (`null` removes it and falls back to the build-time value). */
export function setServerURLOverride(value: string | null, storage: KeyValueStorage | null = defaultStorage()): void {
  safeSet(storage, SERVER_URL_STORAGE_KEY, value === null ? null : value.trim());
}

/** Configured server WebSocket URL, or `null` when no (valid) server is configured. */
export function getServerURL(storage: KeyValueStorage | null = defaultStorage(), env: string | undefined = envServerURL()): string | null {
  const override = getServerURLOverride(storage);
  if (override !== null) return normalizeServerURL(override);
  return normalizeServerURL(env);
}

export function isServerConfigured(storage: KeyValueStorage | null = defaultStorage()): boolean {
  return getServerURL(storage) !== null;
}
