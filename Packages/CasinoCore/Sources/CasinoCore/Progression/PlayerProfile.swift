import Foundation

public struct PlayerStats: Codable, Equatable {
    public var blackjackHands = 0
    public var blackjackWins = 0
    public var blackjacks = 0
    public var pokerHands = 0
    public var pokerWins = 0
    public var slotSpins = 0
    public var slotWins = 0
    public var biggestWin = 0
    public var totalWagered = 0
    public var totalWon = 0
    public var peakChips = 0

    public init() {}
}

public struct MissionProgress: Codable, Equatable, Identifiable {
    public let missionID: String
    public var progress: Int
    public var isClaimed: Bool
    public var id: String { missionID }
}

public struct PlayerSettings: Codable, Equatable {
    public var hapticsEnabled = true
    public var soundEnabled = true
    public var reducedMotion = false
    public init() {}
}

/// Persistenter Spielstand. Chips sind ausschließlich virtuell und haben keinen Geldwert.
public struct PlayerProfile: Codable, Equatable {
    public static let startingChips = 10_000
    public static let currentVersion = 1

    public var version = PlayerProfile.currentVersion
    public var displayName = "Spieler"
    public internal(set) var chips = PlayerProfile.startingChips
    public internal(set) var xp = 0
    public internal(set) var level = 1
    public internal(set) var stats = PlayerStats()
    /// Chips, die gerade auf einem Spieltisch liegen (Einsätze, Poker-Stack).
    /// Wird die App mitten in einer Runde beendet, werden sie beim nächsten Start zurückgebucht.
    public internal(set) var tableEscrow = 0

    public internal(set) var lastLoginBonusDate: Date?
    public internal(set) var loginStreak = 0
    public internal(set) var lastDailyRewardDate: Date?
    public internal(set) var lastRescueDate: Date?

    public internal(set) var missionsDate: Date?
    public internal(set) var dailyMissions: [MissionProgress] = []

    public internal(set) var unlockedAchievements: Set<String> = []
    public internal(set) var claimedAchievements: Set<String> = []
    public internal(set) var completedTutorials: Set<String> = []

    public var settings = PlayerSettings()
    public internal(set) var createdAt = Date()

    public init() {
        stats.peakChips = chips
    }
}
