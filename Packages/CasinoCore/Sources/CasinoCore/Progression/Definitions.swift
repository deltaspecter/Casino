import Foundation

public enum ProgressMetric: String, Codable, CaseIterable {
    case blackjackHands, blackjackWins, blackjacks
    case pokerHands, pokerWins
    case slotSpins, slotWins
    case chipsWagered, biggestWin, level, peakChips, loginStreak
}

public struct MissionDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let metric: ProgressMetric
    public let target: Int
    public let rewardChips: Int
    public let rewardXP: Int
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

public enum RewardTable {
    /// Login-Bonus je Tag der Serie (Tag 7 und folgende wiederholen den letzten Wert der Woche).
    public static let loginStreakRewards = [500, 750, 1_000, 1_500, 2_000, 2_500, 5_000]
    public static let tutorialReward = 1_000
    public static let rescueAmount = 2_500
    public static let rescueThreshold = 100
    public static let rescueCooldown: TimeInterval = 60 * 60

    public static func loginReward(streakDay: Int) -> Int {
        loginStreakRewards[(max(streakDay, 1) - 1) % loginStreakRewards.count]
    }

    public static func dailyReward(level: Int) -> Int { 1_000 + (level - 1) * 100 }

    public static func levelUpReward(newLevel: Int) -> Int { 500 + newLevel * 250 }

    /// XP, die für den Aufstieg von `level` auf `level + 1` nötig sind.
    public static func xpToNextLevel(from level: Int) -> Int { 400 + (level - 1) * 200 }

    /// XP für eine Spielrunde: abhängig vom Einsatz, unabhängig vom Ausgang.
    public static func xp(forStake stake: Int) -> Int { max(1, min(250, stake / 20)) }

    public static let missionsPerDay = 3

    public static let missionPool: [MissionDefinition] = [
        MissionDefinition(id: "bj-hands-10", title: "Spiele 10 Blackjack-Hände", metric: .blackjackHands, target: 10, rewardChips: 750, rewardXP: 100),
        MissionDefinition(id: "bj-wins-5", title: "Gewinne 5 Blackjack-Hände", metric: .blackjackWins, target: 5, rewardChips: 1_000, rewardXP: 120),
        MissionDefinition(id: "bj-natural-1", title: "Erhalte einen Blackjack", metric: .blackjacks, target: 1, rewardChips: 800, rewardXP: 100),
        MissionDefinition(id: "pk-hands-10", title: "Spiele 10 Poker-Hände", metric: .pokerHands, target: 10, rewardChips: 750, rewardXP: 100),
        MissionDefinition(id: "pk-wins-3", title: "Gewinne 3 Poker-Pots", metric: .pokerWins, target: 3, rewardChips: 1_200, rewardXP: 150),
        MissionDefinition(id: "sl-spins-25", title: "Drehe 25 Mal an den Slots", metric: .slotSpins, target: 25, rewardChips: 600, rewardXP: 80),
        MissionDefinition(id: "sl-wins-10", title: "Erziele 10 Slot-Gewinne", metric: .slotWins, target: 10, rewardChips: 900, rewardXP: 110),
        MissionDefinition(id: "wager-5k", title: "Setze insgesamt 5.000 Chips", metric: .chipsWagered, target: 5_000, rewardChips: 1_000, rewardXP: 150),
        MissionDefinition(id: "wager-20k", title: "Setze insgesamt 20.000 Chips", metric: .chipsWagered, target: 20_000, rewardChips: 2_500, rewardXP: 300)
    ]

    public static let achievements: [AchievementDefinition] = [
        AchievementDefinition(id: "first-hand", title: "Erste Hand", detail: "Spiele deine erste Blackjack-Hand.", icon: "suit.spade.fill", metric: .blackjackHands, threshold: 1, rewardChips: 250),
        AchievementDefinition(id: "natural", title: "Natural", detail: "Erhalte deinen ersten Blackjack.", icon: "sparkles", metric: .blackjacks, threshold: 1, rewardChips: 500),
        AchievementDefinition(id: "bj-veteran", title: "Tisch-Veteran", detail: "Spiele 250 Blackjack-Hände.", icon: "rectangle.stack.fill", metric: .blackjackHands, threshold: 250, rewardChips: 5_000),
        AchievementDefinition(id: "first-pot", title: "Erster Pot", detail: "Gewinne deinen ersten Poker-Pot.", icon: "trophy.fill", metric: .pokerWins, threshold: 1, rewardChips: 500),
        AchievementDefinition(id: "card-shark", title: "Kartenhai", detail: "Gewinne 50 Poker-Pots.", icon: "crown.fill", metric: .pokerWins, threshold: 50, rewardChips: 7_500),
        AchievementDefinition(id: "spinner", title: "Walzen-Fan", detail: "Drehe 100 Mal an den Slots.", icon: "arrow.triangle.2.circlepath", metric: .slotSpins, threshold: 100, rewardChips: 1_500),
        AchievementDefinition(id: "big-win", title: "Big Win", detail: "Gewinne 10.000 Chips in einer Runde.", icon: "flame.fill", metric: .biggestWin, threshold: 10_000, rewardChips: 2_500),
        AchievementDefinition(id: "level-5", title: "Aufsteiger", detail: "Erreiche Level 5.", icon: "star.fill", metric: .level, threshold: 5, rewardChips: 2_000),
        AchievementDefinition(id: "level-15", title: "Stammgast", detail: "Erreiche Level 15.", icon: "star.circle.fill", metric: .level, threshold: 15, rewardChips: 10_000),
        AchievementDefinition(id: "high-roller", title: "High Roller", detail: "Besitze 100.000 Chips gleichzeitig.", icon: "diamond.fill", metric: .peakChips, threshold: 100_000, rewardChips: 10_000),
        AchievementDefinition(id: "loyal", title: "Treue Woche", detail: "Melde dich 7 Tage in Folge an.", icon: "calendar", metric: .loginStreak, threshold: 7, rewardChips: 3_000)
    ]

    public static func mission(_ id: String) -> MissionDefinition? { missionPool.first { $0.id == id } }
    public static func achievement(_ id: String) -> AchievementDefinition? { achievements.first { $0.id == id } }
}
