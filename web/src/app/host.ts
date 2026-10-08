import type { RandomSource } from '../core/random'

export interface ToastData {
  id?: number
  icon: string
  title: string
  subtitle?: string
  tint?: 'gold' | 'red' | 'green'
}

/**
 * Was ein Spiel vom App-Modell braucht. Spiele bewegen Chips ausschließlich hierüber.
 * Die Zufallsquelle `random` wird nur an Spiel-Engines übergeben – nichts im Profil beeinflusst sie.
 */
export interface GameHost {
  readonly random: RandomSource
  readonly auxiliaryRandom: RandomSource
  readonly chips: number
  readonly reducedMotion: boolean
  moveToTable(amount: number): boolean
  releaseFromTable(stake: number, payout: number): void
  debit(amount: number): boolean
  credit(amount: number): void
  show(toast: ToastData): void
}
