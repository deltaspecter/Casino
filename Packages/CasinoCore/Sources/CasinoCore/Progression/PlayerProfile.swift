import Foundation

/// Reine Anzeige-Statistik. Wird von keiner Spiel-Engine gelesen.
public struct PlayerStats: Codable, Equatable {
    public var blackjackRounds = 0
    public var blackjackHands = 0
    public var blackjackWins = 0
    public var blackjackPushes = 0
    public var blackjacks = 0
    public var pokerHands = 0
    public var pokerWins = 0
    public var slotSpins = 0
    public var slotWins = 0
    /// Runden (alle Spiele) mit positivem Saldo.
    public var roundsWon = 0
    public var biggestWin = 0
    public var totalWagered = 0
    /// Summe aller positiven Rundensalden.
    public var totalWon = 0
    /// Summe aller negativen Rundensalden (als positive Zahl).
    public var totalLost = 0
    public var peakChips = 0

    public init() {}

    public var gamesPlayed: Int { blackjackRounds + pokerHands + slotSpins }
    public var netResult: Int { totalWon - totalLost }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { max(0, (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0) }
        blackjackRounds = int(.blackjackRounds)
        blackjackHands = int(.blackjackHands)
        blackjackWins = int(.blackjackWins)
        blackjackPushes = int(.blackjackPushes)
        blackjacks = int(.blackjacks)
        pokerHands = int(.pokerHands)
        pokerWins = int(.pokerWins)
        slotSpins = int(.slotSpins)
        slotWins = int(.slotWins)
        roundsWon = int(.roundsWon)
        biggestWin = int(.biggestWin)
        totalWagered = int(.totalWagered)
        totalWon = int(.totalWon)
        totalLost = int(.totalLost)
        peakChips = int(.peakChips)
    }
}

public struct MissionProgress: Codable, Equatable, Identifiable {
    public let missionID: String
    public var progress: Int
    public var isClaimed: Bool
    public var id: String { missionID }
}

public struct PlayerSettings: Codable, Equatable {
    public var hapticsEnabled = true
    public var reducedMotion = false
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? true
        reducedMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reducedMotion)) ?? false
    }
}

/// Persistenter Spielstand. Chips sind ausschließlich virtuell und haben keinen Geldwert.
///
/// Wichtig: Kein Teil dieses Profils wird von einer Spiel-Engine gelesen.
/// Kontostand, Statistik, Missionen und Erfolge haben keinerlei Einfluss auf Karten oder Walzen.
public struct PlayerProfile: Codable, Equatable {
    public static let startingChips = 10_000
    public static let currentVersion = 2

    public var version = PlayerProfile.currentVersion
    public var displayName = "Spieler"
    public internal(set) var chips = PlayerProfile.startingChips
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

    private enum CodingKeys: String, CodingKey {
        case version, displayName, chips, stats, tableEscrow
        case lastLoginBonusDate, loginStreak, lastDailyRewardDate, lastRescueDate
        case missionsDate, dailyMissions
        case unlockedAchievements, claimedAchievements, completedTutorials
        case settings, createdAt
    }

    /// Tolerantes Laden: fehlende oder unbekannte Felder (z. B. aus älteren Versionen)
    /// führen nicht zum Verlust des Spielstands. Ungültige Werte werden bereinigt.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Ohne gültigen Kontostand ist die Datei nicht verwertbar.
        let storedChips = try c.decode(Int.self, forKey: .chips)
        chips = max(0, storedChips)
        version = PlayerProfile.currentVersion
        let name = ((try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        displayName = name.isEmpty ? "Spieler" : String(name.prefix(20))
        stats = ((try? c.decodeIfPresent(PlayerStats.self, forKey: .stats)) ?? nil) ?? PlayerStats()
        tableEscrow = max(0, ((try? c.decodeIfPresent(Int.self, forKey: .tableEscrow)) ?? nil) ?? 0)
        lastLoginBonusDate = (try? c.decodeIfPresent(Date.self, forKey: .lastLoginBonusDate)) ?? nil
        loginStreak = max(0, ((try? c.decodeIfPresent(Int.self, forKey: .loginStreak)) ?? nil) ?? 0)
        lastDailyRewardDate = (try? c.decodeIfPresent(Date.self, forKey: .lastDailyRewardDate)) ?? nil
        lastRescueDate = (try? c.decodeIfPresent(Date.self, forKey: .lastRescueDate)) ?? nil
        missionsDate = (try? c.decodeIfPresent(Date.self, forKey: .missionsDate)) ?? nil
        let missions = ((try? c.decodeIfPresent([MissionProgress].self, forKey: .dailyMissions)) ?? nil) ?? []
        // Nur Missionen behalten, die es (noch) gibt
        dailyMissions = missions.filter { RewardTable.mission($0.missionID) != nil }
        let validAchievements = Set(RewardTable.achievements.map(\.id))
        unlockedAchievements = (((try? c.decodeIfPresent(Set<String>.self, forKey: .unlockedAchievements)) ?? nil) ?? [])
            .intersection(validAchievements)
        claimedAchievements = (((try? c.decodeIfPresent(Set<String>.self, forKey: .claimedAchievements)) ?? nil) ?? [])
            .intersection(unlockedAchievements)
        completedTutorials = ((try? c.decodeIfPresent(Set<String>.self, forKey: .completedTutorials)) ?? nil) ?? []
        settings = ((try? c.decodeIfPresent(PlayerSettings.self, forKey: .settings)) ?? nil) ?? PlayerSettings()
        createdAt = ((try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil) ?? Date()
        stats.peakChips = max(stats.peakChips, chips)
    }
}
