/**
 * Browser connectivity detection (equivalent of the native `ConnectivityMonitor`).
 *
 * - `browserOnline`: `navigator.onLine` plus `online` / `offline` window events.
 * - `serverReachable`: result of probing `GET /health` of the configured server
 *   (`null` = no server configured or not probed yet). The probe uses `mode: 'no-cors'`, so the
 *   server does not need CORS headers – an opaque response means "reachable", a network error
 *   or timeout means "unreachable".
 * - `status`: `'offline'` when the browser is offline or the server is known to be unreachable,
 *   otherwise `'online'`.
 *
 * Offline games (Blackjack, Poker vs. bots, Slots) do not depend on any of this.
 */

export type ConnectivityStatus = 'online' | 'offline';

export interface ConnectivityState {
  readonly status: ConnectivityStatus;
  readonly browserOnline: boolean;
  readonly serverReachable: boolean | null;
  /** ms since 1970 of the last finished probe. */
  readonly lastProbeAt: number | null;
}

export interface ConnectivityOptions {
  /** `GET /health` URL to probe, `null` = no server (status follows the browser only). */
  healthURL?: string | null;
  /** Probe timeout (default 8 s – free hosting tiers may need a cold start). */
  probeTimeoutMs?: number;
  /** Re-probe interval while the server is unreachable (default 30 s, 0 = never). */
  retryIntervalMs?: number;
  /** Injectables for tests. */
  fetch?: typeof globalThis.fetch;
  target?: Pick<EventTarget, 'addEventListener' | 'removeEventListener'> | null;
  documentTarget?: (Pick<EventTarget, 'addEventListener' | 'removeEventListener'> & { visibilityState?: string }) | null;
  isOnline?: () => boolean;
}

type Listener = (state: ConnectivityState) => void;

export class ConnectivityMonitor {
  private _state: ConnectivityState;
  private listeners = new Set<Listener>();
  private started = false;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private probeSeq = 0;
  private healthURL: string | null;
  private readonly probeTimeoutMs: number;
  private readonly retryIntervalMs: number;
  private readonly fetchFn: typeof globalThis.fetch | undefined;
  private readonly target: ConnectivityOptions['target'];
  private readonly documentTarget: ConnectivityOptions['documentTarget'];
  private readonly isOnlineFn: () => boolean;

  constructor(options: ConnectivityOptions = {}) {
    this.healthURL = options.healthURL ?? null;
    this.probeTimeoutMs = options.probeTimeoutMs ?? 8000;
    this.retryIntervalMs = options.retryIntervalMs ?? 30000;
    this.fetchFn = options.fetch ?? (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : undefined);
    this.target = options.target !== undefined ? options.target : typeof window !== 'undefined' ? window : null;
    this.documentTarget = options.documentTarget !== undefined ? options.documentTarget : typeof document !== 'undefined' ? document : null;
    this.isOnlineFn = options.isOnline ?? (() => (typeof navigator !== 'undefined' && typeof navigator.onLine === 'boolean' ? navigator.onLine : true));
    const browserOnline = this.isOnlineFn();
    this._state = { status: browserOnline ? 'online' : 'offline', browserOnline, serverReachable: null, lastProbeAt: null };
  }

  get state(): ConnectivityState { return this._state; }
  get status(): ConnectivityStatus { return this._state.status; }
  get isOnline(): boolean { return this._state.status === 'online'; }

  /** Calls `listener` on every change. Returns an unsubscribe function. */
  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    this.target?.addEventListener('online', this.handleOnline);
    this.target?.addEventListener('offline', this.handleOffline);
    this.documentTarget?.addEventListener('visibilitychange', this.handleVisibility);
    this.update({ browserOnline: this.isOnlineFn() });
    void this.probe();
  }

  stop(): void {
    if (!this.started) return;
    this.started = false;
    this.target?.removeEventListener('online', this.handleOnline);
    this.target?.removeEventListener('offline', this.handleOffline);
    this.documentTarget?.removeEventListener('visibilitychange', this.handleVisibility);
    this.clearRetry();
    this.probeSeq++;
  }

  /** Changes the probed server (e.g. after the server URL was edited). */
  setHealthURL(url: string | null): void {
    this.healthURL = url;
    this.probeSeq++;
    this.clearRetry();
    this.update({ serverReachable: null });
    if (this.started) void this.probe();
  }

  /** Lets the online service report a successful/failed WebSocket session. */
  reportServerReachable(reachable: boolean): void {
    if (!this.healthURL) return;
    this.update({ serverReachable: reachable, lastProbeAt: Date.now() });
    if (reachable) this.clearRetry();
    else this.scheduleRetry();
  }

  /** Probes the server's health endpoint. Resolves with the reachability (`null` = no server). */
  async probe(): Promise<boolean | null> {
    const url = this.healthURL;
    const fetchFn = this.fetchFn;
    if (!url || !fetchFn) return null;
    if (!this._state.browserOnline) return false;
    const seq = ++this.probeSeq;
    const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const timer = setTimeout(() => controller?.abort(), this.probeTimeoutMs);
    let reachable: boolean;
    try {
      await fetchFn(url, { method: 'GET', mode: 'no-cors', cache: 'no-store', signal: controller?.signal });
      reachable = true;
    } catch {
      reachable = false;
    } finally {
      clearTimeout(timer);
    }
    if (seq !== this.probeSeq) return reachable; // superseded
    this.update({ serverReachable: reachable, lastProbeAt: Date.now() });
    if (reachable) this.clearRetry();
    else this.scheduleRetry();
    return reachable;
  }

  private handleOnline = (): void => {
    this.update({ browserOnline: true });
    void this.probe();
  };

  private handleOffline = (): void => {
    this.probeSeq++;
    this.clearRetry();
    this.update({ browserOnline: false });
  };

  private handleVisibility = (): void => {
    if (this.documentTarget?.visibilityState === 'visible') {
      this.update({ browserOnline: this.isOnlineFn() });
      void this.probe();
    }
  };

  private scheduleRetry(): void {
    if (!this.started || this.retryIntervalMs <= 0 || this.retryTimer !== null) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.probe();
    }, this.retryIntervalMs);
  }

  private clearRetry(): void {
    if (this.retryTimer !== null) clearTimeout(this.retryTimer);
    this.retryTimer = null;
  }

  private update(patch: Partial<Omit<ConnectivityState, 'status'>>): void {
    const next = { ...this._state, ...patch };
    const status: ConnectivityStatus = next.browserOnline && next.serverReachable !== false ? 'online' : 'offline';
    const s: ConnectivityState = { ...next, status };
    const prev = this._state;
    if (prev.status === s.status && prev.browserOnline === s.browserOnline && prev.serverReachable === s.serverReachable && prev.lastProbeAt === s.lastProbeAt) return;
    this._state = s;
    for (const l of [...this.listeners]) {
      try { l(s); } catch { /* listener errors must not break the monitor */ }
    }
  }
}
