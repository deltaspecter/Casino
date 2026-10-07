import Foundation

/// Kennzahlen für Missionen und Erfolge – reine Zähler aus der Statistik.
public enum ProgressMetric: String, Codable, CaseIterable {
    case blackjackRounds, blackjackHands, blackjackWins, blackjacks
    case pokerHands, pokerWins
    case slotSpins, slotWins
    case gamesPlayed, roundsWon
    case chipsWagered, biggestWin, peakChips, loginStreak
}

public struct MissionDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let metric: ProgressMetric
    public let target: Int
    public let rewardChips: Int
}

public struct AchievementDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    public let metric: ProgressMetric
    public let threshold: Int
    public let rewardChips: Int
}

public enum GameKind: String, Codable, CaseIterable {
    case blackjack, poker, slots

    public var title: String {
        switch self {
        case .blackjack: return "Blackjack"
        case .poker: return "Poker"
        case .slots: return "Slots"
        }
    }
}

/// Alle Belohnungen sind feste Chip-Beträge. Sie verändern niemals Wahrscheinlichkeiten
/// oder Ergebnisse – die Spiel-Engines kennen das Profil nicht.
public enum RewardTable {
    /// Login-Bonus je Tag der Serie (ab Tag 8 beginnt der Zyklus von vorn).
    public static let loginStreakRewards = [500, 750, 1_000, 1_500, 2_000, 2_500, 5_000]
    public static let dailyReward = 1_000
    public static let tutorialReward = 1_000
    public static let rescueAmount = 2_500
    public static let rescueThreshold = 100
    public static let rescueCooldown: TimeInterval = 60 * 60
    public static let missionsPerDay = 3

    public static func loginReward(streakDay: Int) -> Int {
        loginStreakRewards[(max(streakDay, 1) - 1) % loginStreakRewards.count]
    }

    public static let missionPool: [MissionDefinition] = [
        MissionDefinition(id: "bj-rounds-5", title: "Spiele 5 Blackjack-Runden", metric: .blackjackRounds, target: 5, rewardChips: 500),
        MissionDefinition(id: "bj-rounds-15", title: "Spiele 15 Blackjack-Runden", metric: .blackjackRounds, target: 15, rewardChips: 1_000),
        MissionDefinition(id: "pk-hands-5", title: "Spiele 5 Poker-Runden", metric: .pokerHands, target: 5, rewardChips: 500),
        MissionDefinition(id: "pk-hands-15", title: "Spiele 15 Poker-Runden", metric: .pokerHands, target: 15, rewardChips: 1_000),
        MissionDefinition(id: "sl-spins-10", title: "Spiele 10 Slot-Runden", metric: .slotSpins, target: 10, rewardChips: 500),
        MissionDefinition(id: "sl-spins-30", title: "Spiele 30 Slot-Runden", metric: .slotSpins, target: 30, rewardChips: 1_000),
        MissionDefinition(id: "games-20", title: "Spiele 20 Runden in beliebigen Spielen", metric: .gamesPlayed, target: 20, rewardChips: 1_000)
    ]

    public static let achievements: [AchievementDefinition] = [
        AchievementDefinition(id: "first-win", title: "First Win", detail: "Gewinne deine erste Runde.", icon: "star.fill", metric: .roundsWon, threshold: 1, rewardChips: 250),
        AchievementDefinition(id: "natural", title: "Blackjack", detail: "Erhalte einen Blackjack.", icon: "suit.spade.fill", metric: .blackjacks, threshold: 1, rewardChips: 500),
        AchievementDefinition(id: "poker-win", title: "Poker Win", detail: "Gewinne einen Poker-Pot.", icon: "trophy.fill", metric: .pokerWins, threshold: 1, rewardChips: 500),
        AchievementDefinition(id: "slot-win", title: "Slot Win", detail: "Erziele einen Slot-Gewinn.", icon: "sparkles", metric: .slotWins, threshold: 1, rewardChips: 250),
        AchievementDefinition(id: "games-100", title: "100 Games Played", detail: "Spiele 100 Runden.", icon: "100.circle.fill", metric: .gamesPlayed, threshold: 100, rewardChips: 2_500),
        AchievementDefinition(id: "games-1000", title: "Stammgast", detail: "Spiele 1.000 Runden.", icon: "building.columns.fill", metric: .gamesPlayed, threshold: 1_000, rewardChips: 10_000),
        AchievementDefinition(id: "bj-veteran", title: "Tisch-Veteran", detail: "Spiele 250 Blackjack-Runden.", icon: "rectangle.stack.fill", metric: .blackjackRounds, threshold: 250, rewardChips: 5_000),
        AchievementDefinition(id: "card-shark", title: "Kartenhai", detail: "Gewinne 50 Poker-Pots.", icon: "crown.fill", metric: .pokerWins, threshold: 50, rewardChips: 5_000),
        AchievementDefinition(id: "big-win", title: "Big Win", detail: "Gewinne 10.000 Chips in einer Runde.", icon: "flame.fill", metric: .biggestWin, threshold: 10_000, rewardChips: 2_500),
        AchievementDefinition(id: "high-roller", title: "High Roller", detail: "Besitze 100.000 Chips gleichzeitig.", icon: "diamond.fill", metric: .peakChips, threshold: 100_000, rewardChips: 10_000),
        AchievementDefinition(id: "loyal", title: "Treue Woche", detail: "Hole den Login-Bonus 7 Tage in Folge.", icon: "calendar", metric: .loginStreak, threshold: 7, rewardChips: 3_000)
    ]

    public static func mission(_ id: String) -> MissionDefinition? { missionPool.first { $0.id == id } }
    public static func achievement(_ id: String) -> AchievementDefinition? { achievements.first { $0.id == id } }
}
