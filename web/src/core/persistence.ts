import { PlayerProfile } from './progression/playerProfile';

/** Minimale Speicher-Schnittstelle – passt auf `window.localStorage` und auf `MemoryStorage`. */
export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem?(key: string): void;
}

/** Einfacher In-Memory-Speicher (Tests, oder wenn `localStorage` nicht verfügbar ist). */
export class MemoryStorage implements StorageLike {
  private readonly map = new Map<string, string>();
  getItem(key: string): string | null { return this.map.get(key) ?? null; }
  setItem(key: string, value: string): void { this.map.set(key, value); }
  removeItem(key: string): void { this.map.delete(key); }
  keys(): string[] { return [...this.map.keys()]; }
}

export type ProfileLoadOutcome =
  | { type: 'loaded' }
  | { type: 'created' }
  /** Der beschädigte Inhalt wurde unter `backupKey` gesichert. */
  | { type: 'recoveredFromCorruption'; backupKey: string };

export interface ProfileLoadResult {
  profile: PlayerProfile;
  outcome: ProfileLoadOutcome;
}

/**
 * Speichert den Spielstand als JSON.
 * Ist der Eintrag beschädigt, wird er als Backup zur Seite gelegt und ein neues Profil erstellt,
 * statt die App abstürzen zu lassen.
 */
export class ProfileStore {
  static readonly defaultKey = 'blackcasino.profile';

  readonly storage: StorageLike;
  readonly key: string;

  constructor(storage: StorageLike, key: string = ProfileStore.defaultKey) {
    this.storage = storage;
    this.key = key;
  }

  /** Standard: `localStorage` (falls verfügbar), sonst In-Memory. */
  static defaultStore(): ProfileStore {
    let storage: StorageLike | null = null;
    try {
      const ls = (globalThis as { localStorage?: StorageLike }).localStorage;
      if (ls) storage = ls;
    } catch {
      storage = null;
    }
    return new ProfileStore(storage ?? new MemoryStorage());
  }

  load(): ProfileLoadResult {
    let raw: string | null;
    try {
      raw = this.storage.getItem(this.key);
    } catch {
      raw = null;
    }
    if (raw === null || raw === '') return { profile: new PlayerProfile(), outcome: { type: 'created' } };
    try {
      const profile = PlayerProfile.fromJSONString(raw);
      return { profile, outcome: { type: 'loaded' } };
    } catch {
      const backupKey = `${this.key}.corrupt-${Math.floor(Date.now() / 1000)}`;
      try {
        this.storage.setItem(backupKey, raw);
        if (this.storage.removeItem) this.storage.removeItem(this.key);
        else this.storage.setItem(this.key, '');
      } catch {
        // Backup ist optional – das neue Profil wird trotzdem geliefert.
      }
      return { profile: new PlayerProfile(), outcome: { type: 'recoveredFromCorruption', backupKey } };
    }
  }

  save(profile: PlayerProfile): void {
    this.storage.setItem(this.key, profile.toJSONString());
  }

  reset(): void {
    if (this.storage.removeItem) this.storage.removeItem(this.key);
    else this.storage.setItem(this.key, '');
  }
}
