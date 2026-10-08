import { SystemRandomSource, type RandomSource } from '../core/random'
import { ProfileStore } from '../core/persistence'
import {
  PlayerProfile, RewardTable, type GameEvent, type GameKind, type LoginBonusOffer, type PlayerSettings, type ProgressNotification,
} from '../core/progression'
import { Observable } from './observable'
import type { GameHost, ToastData } from './host'
import { ChipFormat } from '../ui/format'

export type Phase = 'loading' | 'start' | 'lobby'

export type Route =
  | { name: 'menu' }
  | { name: 'blackjack' }
  | { name: 'poker' }
  | { name: 'slotsLobby' }
  | { name: 'slotMachine'; id: string }
  | { name: 'friends' }
  | { name: 'randomMatch' }
  | { name: 'onlineTable' }

export type MenuSheet = 'dailyReward' | 'missions' | 'achievements' | 'statistics' | 'settings' | 'install' | null

let toastSeq = 1

/**
 * Zentraler App-Zustand: Profil, Speicherung, Belohnungen und Benachrichtigungen.
 * Spiele bewegen Chips ausschließlich über diese Klasse.
 */
export class AppModel extends Observable implements GameHost {
  phase: Phase = 'loading'
  route: Route = { name: 'menu' }
  sheet: MenuSheet = null
  toasts: ToastData[] = []
  pendingLoginBonus: LoginBonusOffer | null = null
  storageWarning: string | null = null

  /**
   * Zufallsquelle für Karten und Walzen (kryptografisch sicher, Web Crypto).
   * Sie wird ausschließlich an die Spiel-Engines übergeben – nichts im Profil
   * (Kontostand, Verlauf, Missionen, Erfolge) beeinflusst ihre Werte.
   */
  readonly random: RandomSource = new SystemRandomSource()
  /** Getrennte Quelle für Nicht-Spiel-Zufall (Auswahl der Tagesmissionen, KI-Stil, Optik). */
  readonly auxiliaryRandom: RandomSource = new SystemRandomSource()

  private profileValue: PlayerProfile
  private readonly store: ProfileStore | null
  private saveTimer: number | undefined

  constructor(store: ProfileStore | null = ProfileStore.defaultStore()) {
    super()
    this.store = store
    if (store) {
      const { profile, outcome } = store.load()
      this.profileValue = profile
      if (outcome.type === 'recoveredFromCorruption') this.storageWarning = 'Der Spielstand war beschädigt und wurde zurückgesetzt.'
    } else {
      this.profileValue = new PlayerProfile()
      this.storageWarning = 'Spielstand kann nicht gespeichert werden.'
    }
    if (typeof window !== 'undefined') {
      // Beim Schließen/Wechseln der App sofort speichern.
      window.addEventListener('pagehide', () => this.save())
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') this.save() })
    }
  }

  get profile(): PlayerProfile { return this.profileValue }
  get chips(): number { return this.profileValue.chips }
  get reducedMotion(): boolean { return this.profileValue.settings.reducedMotion }

  private changed() { this.emit() }

  // ---------- Navigation ----------

  setPhase(phase: Phase) {
    this.phase = phase
    this.changed()
  }

  navigate(route: Route) {
    this.route = route
    this.changed()
  }

  openSheet(sheet: MenuSheet) {
    this.sheet = sheet
    this.changed()
  }

  // ---------- Lebenszyklus ----------

  launchFinished() {
    const refunded = this.profileValue.refundTableEscrow()
    if (refunded > 0) {
      this.show({ icon: 'undo', title: 'Unterbrochene Runde storniert', subtitle: `${ChipFormat.string(refunded)} Tisch-Chips wurden zurückgebucht` })
    }
    if (this.storageWarning) this.show({ icon: 'info', title: 'Hinweis', subtitle: this.storageWarning, tint: 'red' })
    this.refreshDay()
    this.save()
  }

  refreshDay() {
    const now = new Date()
    this.profileValue.refreshDailyMissions(now, this.auxiliaryRandom)
    this.pendingLoginBonus = this.profileValue.loginBonusOffer(now)
    this.changed()
  }

  // ---------- Chips ----------

  /** Legt Chips auf den Tisch. Gibt `false` zurück (mit Hinweis), wenn der Kontostand nicht reicht. */
  moveToTable(amount: number): boolean {
    try {
      this.profileValue.moveToTable(amount)
      this.scheduleSave()
      return true
    } catch {
      this.show({ icon: 'info', title: 'Nicht genug Chips', subtitle: 'Hol dir deine tägliche Belohnung im Menü.', tint: 'red' })
      return false
    }
  }

  releaseFromTable(stake: number, payout: number) {
    this.profileValue.releaseFromTable(stake, payout)
    this.scheduleSave()
  }

  setTableEscrow(amount: number) {
    this.profileValue.setTableEscrow(amount)
    this.scheduleSave()
  }

  /** Direktes Abbuchen (Slots: das Ergebnis steht sofort fest). */
  debit(amount: number): boolean {
    try {
      this.profileValue.debit(amount)
      this.scheduleSave()
      return true
    } catch {
      this.show({ icon: 'info', title: 'Nicht genug Chips', subtitle: 'Verringere den Einsatz oder hol dir eine Belohnung.', tint: 'red' })
      return false
    }
  }

  credit(amount: number) {
    this.profileValue.credit(amount)
    this.scheduleSave()
  }

  // ---------- Fortschritt ----------

  record(event: GameEvent) {
    const notes = this.profileValue.record(event)
    this.present(notes)
    this.scheduleSave()
  }

  claimLoginBonus() {
    try {
      const offer = this.profileValue.claimLoginBonus(new Date())
      this.pendingLoginBonus = null
      this.show({ icon: 'gift', title: `Login-Bonus Tag ${offer.streakDay}`, subtitle: `+${ChipFormat.string(offer.amount)} Chips` })
      this.present(this.profileValue.checkAchievements())
      this.save()
    } catch {
      this.pendingLoginBonus = null
      this.changed()
    }
  }

  dismissLoginBonus() {
    this.pendingLoginBonus = null
    this.changed()
  }

  get canClaimDailyReward(): boolean { return this.profileValue.canClaimDailyReward(new Date()) }

  claimDailyReward() {
    try {
      const amount = this.profileValue.claimDailyReward(new Date())
      this.show({ icon: 'gift', title: 'Tägliche Belohnung', subtitle: `+${ChipFormat.string(amount)} Chips` })
      this.save()
    } catch { /* bereits abgeholt */ }
  }

  get canClaimRescue(): boolean { return this.profileValue.canClaimRescue(new Date()) }

  claimRescue() {
    try {
      const amount = this.profileValue.claimRescue(new Date())
      this.show({ icon: 'lifebuoy', title: 'Startpaket', subtitle: `+${ChipFormat.string(amount)} Chips` })
      this.save()
    } catch { /* nicht verfügbar */ }
  }

  claimMission(id: string) {
    const def = RewardTable.mission(id)
    if (!def) return
    try {
      const notes = this.profileValue.claimMission(id)
      this.show({ icon: 'checkCircle', title: 'Mission eingelöst', subtitle: `+${ChipFormat.string(def.rewardChips)} Chips` })
      this.present(notes)
      this.save()
    } catch { /* noch nicht erfüllt */ }
  }

  claimAchievement(id: string) {
    try {
      const amount = this.profileValue.claimAchievement(id)
      this.show({ icon: 'trophy', title: 'Belohnung erhalten', subtitle: `+${ChipFormat.string(amount)} Chips` })
      this.save()
    } catch { /* nicht verfügbar */ }
  }

  isTutorialCompleted(game: GameKind): boolean {
    return this.profileValue.completedTutorials.has(game)
  }

  completeTutorial(game: GameKind) {
    const reward = this.profileValue.completeTutorial(game)
    if (reward <= 0) {
      this.changed()
      return
    }
    this.show({ icon: 'graduation', title: 'Tutorial abgeschlossen', subtitle: `+${ChipFormat.string(reward)} Chips Startbonus` })
    this.save()
  }

  // ---------- Einstellungen ----------

  updateSettings(change: (s: PlayerSettings) => void) {
    change(this.profileValue.settings)
    document.documentElement.classList.toggle('reduced-motion', this.profileValue.settings.reducedMotion)
    this.scheduleSave()
  }

  rename(name: string) {
    const trimmed = name.trim()
    if (!trimmed) return
    this.profileValue.displayName = [...trimmed].slice(0, 20).join('')
    this.scheduleSave()
  }

  resetProgress() {
    this.profileValue = new PlayerProfile()
    this.refreshDay()
    this.save()
    this.show({ icon: 'undo', title: 'Fortschritt zurückgesetzt', subtitle: `Du startest wieder mit ${ChipFormat.string(PlayerProfile.startingChips)} Chips.` })
  }

  // ---------- Benachrichtigungen ----------

  show(toast: ToastData) {
    const entry = { ...toast, id: toastSeq++ }
    this.toasts = [...this.toasts, entry].slice(-3)
    this.changed()
    window.setTimeout(() => {
      this.toasts = this.toasts.filter((t) => t.id !== entry.id)
      this.changed()
    }, 3200)
  }

  private present(notes: ProgressNotification[]) {
    for (const note of notes) {
      if (note.type === 'missionCompleted') {
        this.show({ icon: 'flag', title: 'Mission erfüllt', subtitle: `${note.mission.title} – jetzt einlösen` })
      } else {
        this.show({ icon: 'trophy', title: `Erfolg: ${note.achievement.title}`, subtitle: 'Belohnung unter „Achievements“ abholen' })
      }
    }
  }

  // ---------- Speichern ----------

  /** Bündelt viele kleine Änderungen zu einem Schreibvorgang. */
  private scheduleSave() {
    this.changed()
    window.clearTimeout(this.saveTimer)
    this.saveTimer = window.setTimeout(() => this.save(), 600)
  }

  save() {
    window.clearTimeout(this.saveTimer)
    this.changed()
    if (!this.store) return
    try {
      this.store.save(this.profileValue)
    } catch (e) {
      this.storageWarning = `Speichern fehlgeschlagen: ${(e as Error).message}`
    }
  }
}
