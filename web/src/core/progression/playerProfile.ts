import type { RandomSource } from '../random';
import { Calendar } from './calendar';
import { type GameKind, type MissionDefinition, type ProgressMetric, RewardTable } from './definitions';
import {
  ClaimError, type GameEvent, type LoginBonusOffer, type ProgressNotification, WalletError,
} from './progression';

// MARK: - Hilfsfunktionen für tolerantes Laden

type JSONObject = Record<string, unknown>;

const isObject = (v: unknown): v is JSONObject => typeof v === 'object' && v !== null && !Array.isArray(v);
const intOrNull = (v: unknown): number | null => (typeof v === 'number' && Number.isInteger(v) ? v : null);
const boolOrNull = (v: unknown): boolean | null => (typeof v === 'boolean' ? v : null);

function dateOrNull(v: unknown): Date | null {
  if (typeof v !== 'string') return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t);
}

function stringSetOrNull(v: unknown): Set<string> | null {
  if (!Array.isArray(v) || !v.every((x) => typeof x === 'string')) return null;
  return new Set(v as string[]);
}

/** ISO 8601 ohne Sekundenbruchteile – wie `JSONEncoder.dateEncodingStrategy = .iso8601`. */
function encodeDate(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function prefixCharacters(s: string, n: number): string {
  const Seg = (Intl as unknown as { Segmenter?: new (l?: string, o?: { granularity: string }) => { segment(s: string): Iterable<{ segment: string }> } }).Segmenter;
  const chars = Seg ? Array.from(new Seg(undefined, { granularity: 'grapheme' }).segment(s), (x) => x.segment) : Array.from(s);
  return chars.slice(0, n).join('');
}

// MARK: - PlayerStats

/** Reine Anzeige-Statistik. Wird von keiner Spiel-Engine gelesen. */
export class PlayerStats {
  blackjackRounds = 0;
  blackjackHands = 0;
  blackjackWins = 0;
  blackjackPushes = 0;
  blackjacks = 0;
  pokerHands = 0;
  pokerWins = 0;
  slotSpins = 0;
  slotWins = 0;
  /** Runden (alle Spiele) mit positivem Saldo. */
  roundsWon = 0;
  biggestWin = 0;
  totalWagered = 0;
  /** Summe aller positiven Rundensalden. */
  totalWon = 0;
  /** Summe aller negativen Rundensalden (als positive Zahl). */
  totalLost = 0;
  peakChips = 0;

  get gamesPlayed(): number { return this.blackjackRounds + this.pokerHands + this.slotSpins; }
  get netResult(): number { return this.totalWon - this.totalLost; }

  static readonly fieldNames = [
    'blackjackRounds', 'blackjackHands', 'blackjackWins', 'blackjackPushes', 'blackjacks',
    'pokerHands', 'pokerWins', 'slotSpins', 'slotWins', 'roundsWon', 'biggestWin',
    'totalWagered', 'totalWon', 'totalLost', 'peakChips',
  ] as const;

  /** Tolerantes Laden: fehlende/ungültige Felder → 0, negative Werte → 0. */
  static decode(json: unknown): PlayerStats | null {
    if (!isObject(json)) return null;
    const s = new PlayerStats();
    for (const key of PlayerStats.fieldNames) s[key] = Math.max(0, intOrNull(json[key]) ?? 0);
    return s;
  }

  clone(): PlayerStats {
    const s = new PlayerStats();
    for (const key of PlayerStats.fieldNames) s[key] = this[key];
    return s;
  }

  toJSON(): Record<string, number> {
    const out: Record<string, number> = {};
    for (const key of PlayerStats.fieldNames) out[key] = this[key];
    return out;
  }
}

// MARK: - MissionProgress / PlayerSettings

export interface MissionProgress {
  readonly missionID: string;
  readonly progress: number;
  readonly isClaimed: boolean;
}

export interface PlayerSettings {
  hapticsEnabled: boolean;
  reducedMotion: boolean;
}

export function defaultPlayerSettings(): PlayerSettings {
  return { hapticsEnabled: true, reducedMotion: false };
}

function decodeSettings(json: unknown): PlayerSettings | null {
  if (!isObject(json)) return null;
  return {
    hapticsEnabled: boolOrNull(json.hapticsEnabled) ?? true,
    reducedMotion: boolOrNull(json.reducedMotion) ?? false,
  };
}

function decodeMissions(json: unknown): MissionProgress[] | null {
  if (!Array.isArray(json)) return null;
  const out: MissionProgress[] = [];
  for (const m of json) {
    if (!isObject(m)) return null;
    const missionID = typeof m.missionID === 'string' ? m.missionID : null;
    const progress = intOrNull(m.progress);
    const isClaimed = boolOrNull(m.isClaimed);
    if (missionID === null || progress === null || isClaimed === null) return null;
    out.push({ missionID, progress, isClaimed });
  }
  return out;
}

export class ProfileDecodingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ProfileDecodingError';
  }
}

// MARK: - PlayerProfile

/**
 * Persistenter Spielstand. Chips sind ausschließlich virtuell und haben keinen Geldwert.
 *
 * Wichtig: Kein Teil dieses Profils wird von einer Spiel-Engine gelesen.
 * Kontostand, Statistik, Missionen und Erfolge haben keinerlei Einfluss auf Karten oder Walzen.
 *
 * Mutierende Methoden verändern das Objekt selbst (wie `mutating func` in Swift);
 * mit `clone()` lässt sich eine unabhängige Kopie erzeugen.
 */
export class PlayerProfile {
  static readonly startingChips = 10_000;
  static readonly currentVersion = 2;

  version = PlayerProfile.currentVersion;
  displayName = 'Spieler';
  settings: PlayerSettings = defaultPlayerSettings();

  private _chips = PlayerProfile.startingChips;
  private _stats = new PlayerStats();
  private _tableEscrow = 0;
  private _lastLoginBonusDate: Date | null = null;
  private _loginStreak = 0;
  private _lastDailyRewardDate: Date | null = null;
  private _lastRescueDate: Date | null = null;
  private _missionsDate: Date | null = null;
  private _dailyMissions: MissionProgress[] = [];
  private _unlockedAchievements = new Set<string>();
  private _claimedAchievements = new Set<string>();
  private _completedTutorials = new Set<string>();
  private _createdAt = new Date();

  constructor() {
    this._stats.peakChips = this._chips;
  }

  // MARK: Lesezugriff (Swift: `internal(set)`)

  get chips(): number { return this._chips; }
  get stats(): Readonly<PlayerStats> { return this._stats; }
  /**
   * Chips, die gerade auf einem Spieltisch liegen (Einsätze, Poker-Stack).
   * Wird die App mitten in einer Runde beendet, werden sie beim nächsten Start zurückgebucht.
   */
  get tableEscrow(): number { return this._tableEscrow; }
  get lastLoginBonusDate(): Date | null { return this._lastLoginBonusDate; }
  get loginStreak(): number { return this._loginStreak; }
  get lastDailyRewardDate(): Date | null { return this._lastDailyRewardDate; }
  get lastRescueDate(): Date | null { return this._lastRescueDate; }
  get missionsDate(): Date | null { return this._missionsDate; }
  get dailyMissions(): readonly MissionProgress[] { return this._dailyMissions; }
  get unlockedAchievements(): ReadonlySet<string> { return this._unlockedAchievements; }
  get claimedAchievements(): ReadonlySet<string> { return this._claimedAchievements; }
  get completedTutorials(): ReadonlySet<string> { return this._completedTutorials; }
  get createdAt(): Date { return this._createdAt; }

  // MARK: Kodierung

  /** JSON-Darstellung mit denselben Schlüsseln wie die Swift-Version. */
  toJSON(): Record<string, unknown> {
    const out: Record<string, unknown> = {
      chips: this._chips,
      claimedAchievements: [...this._claimedAchievements].sort(),
      completedTutorials: [...this._completedTutorials].sort(),
      createdAt: encodeDate(this._createdAt),
      dailyMissions: this._dailyMissions.map((m) => ({ isClaimed: m.isClaimed, missionID: m.missionID, progress: m.progress })),
      displayName: this.displayName,
      loginStreak: this._loginStreak,
      settings: { hapticsEnabled: this.settings.hapticsEnabled, reducedMotion: this.settings.reducedMotion },
      stats: this._stats.toJSON(),
      tableEscrow: this._tableEscrow,
      unlockedAchievements: [...this._unlockedAchievements].sort(),
      version: this.version,
    };
    // Optionale Daten werden (wie bei Swift `encodeIfPresent`) weggelassen, wenn nicht gesetzt.
    if (this._lastDailyRewardDate) out.lastDailyRewardDate = encodeDate(this._lastDailyRewardDate);
    if (this._lastLoginBonusDate) out.lastLoginBonusDate = encodeDate(this._lastLoginBonusDate);
    if (this._lastRescueDate) out.lastRescueDate = encodeDate(this._lastRescueDate);
    if (this._missionsDate) out.missionsDate = encodeDate(this._missionsDate);
    return Object.fromEntries(Object.entries(out).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  }

  toJSONString(pretty = true): string {
    return JSON.stringify(this.toJSON(), null, pretty ? 2 : undefined);
  }

  /**
   * Tolerantes Laden: fehlende oder unbekannte Felder (z. B. aus älteren Versionen)
   * führen nicht zum Verlust des Spielstands. Ungültige Werte werden bereinigt.
   * Wirft `ProfileDecodingError`, wenn kein gültiger Kontostand (`chips`) vorhanden ist.
   */
  static decode(json: unknown): PlayerProfile {
    if (!isObject(json)) throw new ProfileDecodingError('Profil ist kein JSON-Objekt');
    // Ohne gültigen Kontostand ist die Datei nicht verwertbar.
    const storedChips = intOrNull(json.chips);
    if (storedChips === null) throw new ProfileDecodingError('Kontostand fehlt oder ist ungültig');

    const p = new PlayerProfile();
    p._chips = Math.max(0, storedChips);
    p.version = PlayerProfile.currentVersion;
    const name = typeof json.displayName === 'string' ? json.displayName.trim() : '';
    p.displayName = name === '' ? 'Spieler' : prefixCharacters(name, 20);
    p._stats = PlayerStats.decode(json.stats) ?? new PlayerStats();
    p._tableEscrow = Math.max(0, intOrNull(json.tableEscrow) ?? 0);
    p._lastLoginBonusDate = dateOrNull(json.lastLoginBonusDate);
    p._loginStreak = Math.max(0, intOrNull(json.loginStreak) ?? 0);
    p._lastDailyRewardDate = dateOrNull(json.lastDailyRewardDate);
    p._lastRescueDate = dateOrNull(json.lastRescueDate);
    p._missionsDate = dateOrNull(json.missionsDate);
    // Nur Missionen behalten, die es (noch) gibt
    p._dailyMissions = (decodeMissions(json.dailyMissions) ?? []).filter((m) => RewardTable.mission(m.missionID) !== null);
    const validAchievements = new Set(RewardTable.achievements.map((a) => a.id));
    p._unlockedAchievements = new Set([...(stringSetOrNull(json.unlockedAchievements) ?? [])].filter((id) => validAchievements.has(id)));
    p._claimedAchievements = new Set([...(stringSetOrNull(json.claimedAchievements) ?? [])].filter((id) => p._unlockedAchievements.has(id)));
    p._completedTutorials = stringSetOrNull(json.completedTutorials) ?? new Set();
    p.settings = decodeSettings(json.settings) ?? defaultPlayerSettings();
    p._createdAt = dateOrNull(json.createdAt) ?? new Date();
    p._stats.peakChips = Math.max(p._stats.peakChips, p._chips);
    return p;
  }

  /** Parst einen JSON-Text; wirft bei ungültigem JSON oder fehlendem Kontostand. */
  static fromJSONString(text: string): PlayerProfile {
    return PlayerProfile.decode(JSON.parse(text) as unknown);
  }

  /** Unabhängige Kopie (Swift-Werttyp-Semantik). */
  clone(): PlayerProfile {
    const p = new PlayerProfile();
    p.version = this.version;
    p.displayName = this.displayName;
    p.settings = { ...this.settings };
    p._chips = this._chips;
    p._stats = this._stats.clone();
    p._tableEscrow = this._tableEscrow;
    p._lastLoginBonusDate = this._lastLoginBonusDate;
    p._loginStreak = this._loginStreak;
    p._lastDailyRewardDate = this._lastDailyRewardDate;
    p._lastRescueDate = this._lastRescueDate;
    p._missionsDate = this._missionsDate;
    p._dailyMissions = [...this._dailyMissions];
    p._unlockedAchievements = new Set(this._unlockedAchievements);
    p._claimedAchievements = new Set(this._claimedAchievements);
    p._completedTutorials = new Set(this._completedTutorials);
    p._createdAt = this._createdAt;
    return p;
  }

  // MARK: - Wallet

  /** Bucht Chips ab. Wirft bei Betrag ≤ 0 oder zu geringem Kontostand – der Kontostand wird nie negativ. */
  debit(amount: number): void {
    if (!Number.isInteger(amount) || amount <= 0) throw WalletError.invalidAmount();
    if (amount > this._chips) throw WalletError.insufficientChips(amount, this._chips);
    this._chips -= amount;
  }

  /** Schreibt Chips gut. Beträge ≤ 0 (oder nicht ganzzahlig) werden ignoriert. */
  credit(amount: number): void {
    if (!Number.isInteger(amount) || amount <= 0) return;
    this._chips += amount;
    this._stats.peakChips = Math.max(this._stats.peakChips, this._chips);
  }

  // MARK: - Tisch-Treuhand

  /** Bucht Chips vom Kontostand auf den Tisch (Einsatz, Buy-in). */
  moveToTable(amount: number): void {
    this.debit(amount);
    this._tableEscrow += amount;
  }

  /** Gibt den Tisch-Einsatz frei und schreibt die Auszahlung gut. */
  releaseFromTable(stake: number, payout: number): void {
    this._tableEscrow = Math.max(0, this._tableEscrow - stake);
    this.credit(payout);
  }

  /** Setzt den Treuhand-Betrag (z. B. aktueller Poker-Stack nach einer Hand). */
  setTableEscrow(amount: number): void {
    this._tableEscrow = Math.max(0, amount);
  }

  /** Bucht nach einem unerwarteten Beenden alle Tisch-Chips zurück. */
  refundTableEscrow(): number {
    const amount = this._tableEscrow;
    this._tableEscrow = 0;
    this.credit(amount);
    return amount;
  }

  // MARK: - Tägliche Belohnungen

  loginBonusOffer(now: Date, calendar: Calendar = Calendar.current): LoginBonusOffer | null {
    const last = this._lastLoginBonusDate;
    if (last) {
      const days = PlayerProfile.daysBetween(last, now, calendar);
      if (days <= 0) return null;
      const streak = days === 1 ? this._loginStreak + 1 : 1;
      return { streakDay: streak, amount: RewardTable.loginReward(streak) };
    }
    return { streakDay: 1, amount: RewardTable.loginReward(1) };
  }

  claimLoginBonus(now: Date, calendar: Calendar = Calendar.current): LoginBonusOffer {
    const offer = this.loginBonusOffer(now, calendar);
    if (!offer) throw new ClaimError('alreadyClaimed');
    this._loginStreak = offer.streakDay;
    this._lastLoginBonusDate = now;
    this.credit(offer.amount);
    return offer;
  }

  canClaimDailyReward(now: Date, calendar: Calendar = Calendar.current): boolean {
    const last = this._lastDailyRewardDate;
    if (!last) return true;
    return !calendar.isDateInSameDayAs(last, now) && last.getTime() < now.getTime();
  }

  /** Nächster Zeitpunkt, an dem die tägliche Belohnung wieder verfügbar ist (`null` = jetzt verfügbar). */
  nextDailyReward(now: Date, calendar: Calendar = Calendar.current): Date | null {
    if (this.canClaimDailyReward(now, calendar)) return null;
    return calendar.startOfDayAdding(1, now);
  }

  claimDailyReward(now: Date, calendar: Calendar = Calendar.current): number {
    if (!this.canClaimDailyReward(now, calendar)) throw new ClaimError('alreadyClaimed');
    const amount = RewardTable.dailyReward;
    this._lastDailyRewardDate = now;
    this.credit(amount);
    return amount;
  }

  /** „Rettungspaket“, damit niemand dauerhaft ohne Chips dasteht. */
  canClaimRescue(now: Date): boolean {
    if (this._chips >= RewardTable.rescueThreshold) return false;
    const last = this._lastRescueDate;
    if (!last) return true;
    return (now.getTime() - last.getTime()) / 1000 >= RewardTable.rescueCooldown;
  }

  claimRescue(now: Date): number {
    if (!this.canClaimRescue(now)) throw new ClaimError('notAvailable');
    this._lastRescueDate = now;
    this.credit(RewardTable.rescueAmount);
    return RewardTable.rescueAmount;
  }

  /** Einmaliger Tutorial-Bonus je Spiel; gibt 0 zurück, wenn bereits erhalten. */
  completeTutorial(game: GameKind): number {
    if (this._completedTutorials.has(game)) return 0;
    this._completedTutorials.add(game);
    this.credit(RewardTable.tutorialReward);
    return RewardTable.tutorialReward;
  }

  // MARK: - Missionen

  /**
   * Stellt sicher, dass für den heutigen Tag Missionen vorhanden sind.
   * Die Auswahl der Tagesmissionen erfolgt zufällig aus dem Pool – mit einer eigenen
   * Zufallsquelle, die mit den Spielen nichts zu tun hat.
   */
  refreshDailyMissions(now: Date, random: RandomSource, calendar: Calendar = Calendar.current): void {
    const date = this._missionsDate;
    if (date && calendar.isDateInSameDayAs(date, now) && this._dailyMissions.length > 0) return;
    const pool: MissionDefinition[] = [...RewardTable.missionPool];
    random.shuffle(pool);
    this._dailyMissions = pool.slice(0, RewardTable.missionsPerDay).map((m) => ({ missionID: m.id, progress: 0, isClaimed: false }));
    this._missionsDate = now;
  }

  isMissionComplete(mission: MissionProgress): boolean {
    const def = RewardTable.mission(mission.missionID);
    if (!def) return false;
    return mission.progress >= def.target;
  }

  claimMission(id: string): ProgressNotification[] {
    const index = this._dailyMissions.findIndex((m) => m.missionID === id);
    const def = RewardTable.mission(id);
    if (index < 0 || !def) throw new ClaimError('notAvailable');
    const mission = this._dailyMissions[index]!;
    if (mission.isClaimed) throw new ClaimError('alreadyClaimed');
    if (mission.progress < def.target) throw new ClaimError('notAvailable');
    this.replaceMission(index, { ...mission, isClaimed: true });
    this.credit(def.rewardChips);
    return this.checkAchievements();
  }

  private replaceMission(index: number, mission: MissionProgress): void {
    const next = [...this._dailyMissions];
    next[index] = mission;
    this._dailyMissions = next;
  }

  // MARK: - Erfolge

  metricValue(metric: ProgressMetric): number {
    const s = this._stats;
    switch (metric) {
      case 'blackjackRounds': return s.blackjackRounds;
      case 'blackjackHands': return s.blackjackHands;
      case 'blackjackWins': return s.blackjackWins;
      case 'blackjacks': return s.blackjacks;
      case 'pokerHands': return s.pokerHands;
      case 'pokerWins': return s.pokerWins;
      case 'slotSpins': return s.slotSpins;
      case 'slotWins': return s.slotWins;
      case 'gamesPlayed': return s.gamesPlayed;
      case 'roundsWon': return s.roundsWon;
      case 'chipsWagered': return s.totalWagered;
      case 'biggestWin': return s.biggestWin;
      case 'peakChips': return s.peakChips;
      case 'loginStreak': return this._loginStreak;
    }
  }

  checkAchievements(): ProgressNotification[] {
    const notes: ProgressNotification[] = [];
    for (const def of RewardTable.achievements) {
      if (this._unlockedAchievements.has(def.id)) continue;
      if (this.metricValue(def.metric) >= def.threshold) {
        this._unlockedAchievements.add(def.id);
        notes.push({ type: 'achievementUnlocked', achievement: def });
      }
    }
    return notes;
  }

  claimAchievement(id: string): number {
    const def = RewardTable.achievement(id);
    if (!def || !this._unlockedAchievements.has(id)) throw new ClaimError('notAvailable');
    if (this._claimedAchievements.has(id)) throw new ClaimError('alreadyClaimed');
    this._claimedAchievements.add(id);
    this.credit(def.rewardChips);
    return def.rewardChips;
  }

  // MARK: - Spielereignisse

  /**
   * Verbucht Statistik, Missionsfortschritt und Erfolge.
   * Chips werden hier **nicht** bewegt – das passiert über die Wallet-Funktionen.
   * Diese Daten fließen in keine Spiel-Engine zurück.
   */
  record(event: GameEvent): ProgressNotification[] {
    const deltas = new Map<ProgressMetric, number>();
    const stats = this._stats;
    let stake: number;
    let net: number;

    switch (event.type) {
      case 'blackjackRound':
        stake = event.stake; net = event.payout - event.stake;
        stats.blackjackRounds += 1;
        stats.blackjackHands += event.hands;
        stats.blackjackWins += event.handsWon;
        stats.blackjackPushes += event.pushes;
        stats.blackjacks += event.blackjacks;
        deltas.set('blackjackRounds', 1);
        deltas.set('blackjackHands', event.hands);
        deltas.set('blackjackWins', event.handsWon);
        deltas.set('blackjacks', event.blackjacks);
        break;
      case 'pokerHand':
        stake = event.contributed; net = event.won - event.contributed;
        stats.pokerHands += 1;
        deltas.set('pokerHands', 1);
        if (event.won > 0) {
          stats.pokerWins += 1;
          deltas.set('pokerWins', 1);
        }
        break;
      case 'slotSpin':
        stake = event.bet; net = event.payout - event.bet;
        stats.slotSpins += 1;
        deltas.set('slotSpins', 1);
        if (event.payout > 0) {
          stats.slotWins += 1;
          deltas.set('slotWins', 1);
        }
        break;
    }

    deltas.set('gamesPlayed', 1);
    stats.totalWagered += stake;
    deltas.set('chipsWagered', stake);
    if (net > 0) {
      stats.roundsWon += 1;
      deltas.set('roundsWon', 1);
      stats.totalWon += net;
      stats.biggestWin = Math.max(stats.biggestWin, net);
    } else if (net < 0) {
      stats.totalLost += -net;
    }

    const notes: ProgressNotification[] = [];
    this._dailyMissions.forEach((mission, i) => {
      if (mission.isClaimed) return;
      const def = RewardTable.mission(mission.missionID);
      const delta = def ? deltas.get(def.metric) : undefined;
      if (!def || delta === undefined) return;
      const wasComplete = mission.progress >= def.target;
      const progress = Math.min(def.target, mission.progress + delta);
      this.replaceMission(i, { ...mission, progress });
      if (!wasComplete && progress >= def.target) notes.push({ type: 'missionCompleted', mission: def });
    });
    notes.push(...this.checkAchievements());
    return notes;
  }

  // MARK: - Hilfsfunktionen

  static daysBetween(from: Date, to: Date, calendar: Calendar): number {
    return calendar.daysBetween(from, to);
  }
}
