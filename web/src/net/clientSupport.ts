/**
 * Port of CasinoNet/ClientSupport.swift: room codes, double-tap protection and reconnect backoff.
 */

/** Room codes: 6 characters without easily confused characters (no 0/O, 1/I). */
export const RoomCode = {
  alphabet: 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
  length: 6,

  /** Normalizes user input (whitespace, lower case, dashes) or returns `null`. */
  normalize(input: string): string | null {
    const cleaned = Array.from(input.toUpperCase()).filter((c) => !/\s/u.test(c) && c !== '-');
    if (cleaned.length !== RoomCode.length) return null;
    if (!cleaned.every((c) => RoomCode.alphabet.includes(c))) return null;
    return cleaned.join('');
  },

  isValid(input: string): boolean {
    return RoomCode.normalize(input) !== null;
  },

  /** Random code (crypto RNG; 256 is a multiple of 32, so `byte % 32` is unbiased). */
  generate(): string {
    const bytes = new Uint8Array(RoomCode.length);
    globalThis.crypto.getRandomValues(bytes);
    return Array.from(bytes, (b) => RoomCode.alphabet[b % RoomCode.alphabet.length]).join('');
  },
} as const;

/** Uppercase UUID v4 (Swift `UUID().uuidString` format). Works in insecure contexts too. */
export function makeUUID(): string {
  const c = globalThis.crypto;
  if (c && typeof c.randomUUID === 'function') {
    try {
      return c.randomUUID().toUpperCase();
    } catch {
      // randomUUID is unavailable outside secure contexts in some browsers – fall through
    }
  }
  const b = new Uint8Array(16);
  if (c && typeof c.getRandomValues === 'function') c.getRandomValues(b);
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6]! & 0x0f) | 0x40;
  b[8] = (b[8]! & 0x3f) | 0x80;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('').toUpperCase();
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Prevents double actions: while an action is unconfirmed, no further one is sent. */
export class ActionGate {
  private _pendingActionID: string | null = null;
  private _pendingSince: number | null = null;

  constructor(private readonly makeID: () => string = makeUUID) {}

  get pendingActionID(): string | null { return this._pendingActionID; }
  /** Milliseconds since 1970 when the pending action began. */
  get pendingSince(): number | null { return this._pendingSince; }
  get isBusy(): boolean { return this._pendingActionID !== null; }

  /** Starts an action and returns its id – or `null` if an action is already pending. */
  begin(now: number = Date.now()): string | null {
    if (this._pendingActionID !== null) return null;
    const id = this.makeID();
    this._pendingActionID = id;
    this._pendingSince = now;
    return id;
  }

  /** Server answered an action. */
  resolve(actionID: string): void {
    if (this._pendingActionID !== null && this._pendingActionID.toUpperCase() === actionID.toUpperCase()) this.reset();
  }

  /** New state from the server or connection loss: discard the pending action. */
  reset(): void {
    this._pendingActionID = null;
    this._pendingSince = null;
  }
}

/** Wait times (seconds) for reconnect attempts (exponential, capped). */
export class ReconnectPolicy {
  static readonly defaultDelays: readonly number[] = [0.5, 1, 2, 4, 8, 15, 15, 15];

  constructor(readonly delays: readonly number[] = ReconnectPolicy.defaultDelays) {}

  /** Total time (seconds) that reconnecting is tried before the connection counts as lost. */
  get totalDuration(): number {
    return this.delays.reduce((a, b) => a + b, 0);
  }

  /** Delay in seconds for the given attempt (0-based) or `null` when attempts are exhausted. */
  delay(forAttempt: number): number | null {
    return forAttempt >= 0 && forAttempt < this.delays.length ? this.delays[forAttempt]! : null;
  }

  /** Same as `delay`, in milliseconds. */
  delayMs(forAttempt: number): number | null {
    const d = this.delay(forAttempt);
    return d === null ? null : Math.round(d * 1000);
  }
}
