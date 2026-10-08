/** Kennzahlen für Missionen und Erfolge – reine Zähler aus der Statistik. */
export type ProgressMetric =
  | 'blackjackRounds' | 'blackjackHands' | 'blackjackWins' | 'blackjacks'
  | 'pokerHands' | 'pokerWins'
  | 'slotSpins' | 'slotWins'
  | 'gamesPlayed' | 'roundsWon'
  | 'chipsWagered' | 'biggestWin' | 'peakChips' | 'loginStreak';

export const ALL_PROGRESS_METRICS: readonly ProgressMetric[] = [
  'blackjackRounds', 'blackjackHands', 'blackjackWins', 'blackjacks',
  'pokerHands', 'pokerWins', 'slotSpins', 'slotWins', 'gamesPlayed', 'roundsWon',
  'chipsWagered', 'biggestWin', 'peakChips', 'loginStreak',
];

export interface MissionDefinition {
  readonly id: string;
  readonly title: string;
  readonly metric: ProgressMetric;
  readonly target: number;
  readonly rewardChips: number;
}

export interface AchievementDefinition {
  readonly id: string;
  readonly title: string;
  readonly detail: string;
  /** SF-Symbol-Name aus der iPad-App (für ein Icon-Mapping im Web). */
  readonly icon: string;
  readonly metric: ProgressMetric;
  readonly threshold: number;
  readonly rewardChips: number;
}

export type GameKind = 'blackjack' | 'poker' | 'slots';
export const ALL_GAME_KINDS: readonly GameKind[] = ['blackjack', 'poker', 'slots'];

export function gameKindTitle(kind: GameKind): string {
  switch (kind) {
    case 'blackjack': return 'Blackjack';
    case 'poker': return 'Poker';
    case 'slots': return 'Slots';
  }
}

const mission = (id: string, title: string, metric: ProgressMetric, target: number, rewardChips: number): MissionDefinition =>
  Object.freeze({ id, title, metric, target, rewardChips });

const achievement = (
  id: string, title: string, detail: string, icon: string, metric: ProgressMetric, threshold: number, rewardChips: number,
): AchievementDefinition => Object.freeze({ id, title, detail, icon, metric, threshold, rewardChips });

const loginStreakRewards: readonly number[] = Object.freeze([500, 750, 1_000, 1_500, 2_000, 2_500, 5_000]);

const missionPool: readonly MissionDefinition[] = Object.freeze([
  mission('bj-rounds-5', 'Spiele 5 Blackjack-Runden', 'blackjackRounds', 5, 500),
  mission('bj-rounds-15', 'Spiele 15 Blackjack-Runden', 'blackjackRounds', 15, 1_000),
  mission('pk-hands-5', 'Spiele 5 Poker-Runden', 'pokerHands', 5, 500),
  mission('pk-hands-15', 'Spiele 15 Poker-Runden', 'pokerHands', 15, 1_000),
  mission('sl-spins-10', 'Spiele 10 Slot-Runden', 'slotSpins', 10, 500),
  mission('sl-spins-30', 'Spiele 30 Slot-Runden', 'slotSpins', 30, 1_000),
  mission('games-20', 'Spiele 20 Runden in beliebigen Spielen', 'gamesPlayed', 20, 1_000),
]);

const achievements: readonly AchievementDefinition[] = Object.freeze([
  achievement('first-win', 'First Win', 'Gewinne deine erste Runde.', 'star.fill', 'roundsWon', 1, 250),
  achievement('natural', 'Blackjack', 'Erhalte einen Blackjack.', 'suit.spade.fill', 'blackjacks', 1, 500),
  achievement('poker-win', 'Poker Win', 'Gewinne einen Poker-Pot.', 'trophy.fill', 'pokerWins', 1, 500),
  achievement('slot-win', 'Slot Win', 'Erziele einen Slot-Gewinn.', 'sparkles', 'slotWins', 1, 250),
  achievement('games-100', '100 Games Played', 'Spiele 100 Runden.', '100.circle.fill', 'gamesPlayed', 100, 2_500),
  achievement('games-1000', 'Stammgast', 'Spiele 1.000 Runden.', 'building.columns.fill', 'gamesPlayed', 1_000, 10_000),
  achievement('bj-veteran', 'Tisch-Veteran', 'Spiele 250 Blackjack-Runden.', 'rectangle.stack.fill', 'blackjackRounds', 250, 5_000),
  achievement('card-shark', 'Kartenhai', 'Gewinne 50 Poker-Pots.', 'crown.fill', 'pokerWins', 50, 5_000),
  achievement('big-win', 'Big Win', 'Gewinne 10.000 Chips in einer Runde.', 'flame.fill', 'biggestWin', 10_000, 2_500),
  achievement('high-roller', 'High Roller', 'Besitze 100.000 Chips gleichzeitig.', 'diamond.fill', 'peakChips', 100_000, 10_000),
  achievement('loyal', 'Treue Woche', 'Hole den Login-Bonus 7 Tage in Folge.', 'calendar', 'loginStreak', 7, 3_000),
]);

/**
 * Alle Belohnungen sind feste Chip-Beträge. Sie verändern niemals Wahrscheinlichkeiten
 * oder Ergebnisse – die Spiel-Engines kennen das Profil nicht.
 */
export const RewardTable = {
  /** Login-Bonus je Tag der Serie (ab Tag 8 beginnt der Zyklus von vorn). */
  loginStreakRewards,
  dailyReward: 1_000,
  tutorialReward: 1_000,
  rescueAmount: 2_500,
  rescueThreshold: 100,
  /** Sekunden (wie `TimeInterval` in Swift): 1 Stunde */
  rescueCooldown: 60 * 60,
  missionsPerDay: 3,

  loginReward(streakDay: number): number {
    return loginStreakRewards[(Math.max(streakDay, 1) - 1) % loginStreakRewards.length]!;
  },

  missionPool,
  achievements,

  mission(id: string): MissionDefinition | null {
    return missionPool.find((m) => m.id === id) ?? null;
  },
  achievement(id: string): AchievementDefinition | null {
    return achievements.find((a) => a.id === id) ?? null;
  },
} as const;
