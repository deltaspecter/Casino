import Foundation

public enum WalletError: Error, Equatable {
    case insufficientChips(needed: Int, available: Int)
    case invalidAmount
}

public enum ClaimError: Error, Equatable {
    case notAvailable
    case alreadyClaimed
}

/// Ergebnis einer Spielrunde aus Sicht des Fortschrittssystems.
public enum GameEvent: Equatable {
    case blackjackRound(stake: Int, payout: Int, handsWon: Int, pushes: Int, blackjacks: Int, hands: Int)
    case pokerHand(contributed: Int, won: Int)
    case slotSpin(bet: Int, payout: Int)
}

public enum ProgressNotification: Equatable {
    case missionCompleted(MissionDefinition)
    case achievementUnlocked(AchievementDefinition)
}

public struct LoginBonusOffer: Equatable {
    public let streakDay: Int
    public let amount: Int
}

public extension PlayerProfile {
    // MARK: - Wallet

    mutating func debit(_ amount: Int) throws {
        guard amount > 0 else { throw WalletError.invalidAmount }
        guard amount <= chips else { throw WalletError.insufficientChips(needed: amount, available: chips) }
        chips -= amount
    }

    mutating func credit(_ amount: Int) {
        guard amount > 0 else { return }
        chips += amount
        stats.peakChips = max(stats.peakChips, chips)
    }

    // MARK: - Tisch-Treuhand

    /// Bucht Chips vom Kontostand auf den Tisch (Einsatz, Buy-in).
    mutating func moveToTable(_ amount: Int) throws {
        try debit(amount)
        tableEscrow += amount
    }

    /// Gibt den Tisch-Einsatz frei und schreibt die Auszahlung gut.
    mutating func releaseFromTable(stake: Int, payout: Int) {
        tableEscrow = max(0, tableEscrow - stake)
        credit(payout)
    }

    /// Setzt den Treuhand-Betrag (z. B. aktueller Poker-Stack nach einer Hand).
    mutating func setTableEscrow(_ amount: Int) {
        tableEscrow = max(0, amount)
    }

    /// Bucht nach einem unerwarteten Beenden alle Tisch-Chips zurück.
    @discardableResult
    mutating func refundTableEscrow() -> Int {
        let amount = tableEscrow
        tableEscrow = 0
        credit(amount)
        return amount
    }

    // MARK: - Tägliche Belohnungen

    func loginBonusOffer(now: Date, calendar: Calendar = .current) -> LoginBonusOffer? {
        if let last = lastLoginBonusDate {
            let days = Self.daysBetween(last, now, calendar)
            if days <= 0 { return nil }
            let streak = days == 1 ? loginStreak + 1 : 1
            return LoginBonusOffer(streakDay: streak, amount: RewardTable.loginReward(streakDay: streak))
        }
        return LoginBonusOffer(streakDay: 1, amount: RewardTable.loginReward(streakDay: 1))
    }

    @discardableResult
    mutating func claimLoginBonus(now: Date, calendar: Calendar = .current) throws -> LoginBonusOffer {
        guard let offer = loginBonusOffer(now: now, calendar: calendar) else { throw ClaimError.alreadyClaimed }
        loginStreak = offer.streakDay
        lastLoginBonusDate = now
        credit(offer.amount)
        return offer
    }

    func canClaimDailyReward(now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastDailyRewardDate else { return true }
        return !calendar.isDate(last, inSameDayAs: now) && last < now
    }

    /// Nächster Zeitpunkt, an dem die tägliche Belohnung wieder verfügbar ist.
    func nextDailyReward(now: Date, calendar: Calendar = .current) -> Date? {
        guard !canClaimDailyReward(now: now, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    @discardableResult
    mutating func claimDailyReward(now: Date, calendar: Calendar = .current) throws -> Int {
        guard canClaimDailyReward(now: now, calendar: calendar) else { throw ClaimError.alreadyClaimed }
        let amount = RewardTable.dailyReward
        lastDailyRewardDate = now
        credit(amount)
        return amount
    }

    /// „Rettungspaket“, damit niemand dauerhaft ohne Chips dasteht.
    func canClaimRescue(now: Date) -> Bool {
        guard chips < RewardTable.rescueThreshold else { return false }
        guard let last = lastRescueDate else { return true }
        return now.timeIntervalSince(last) >= RewardTable.rescueCooldown
    }

    @discardableResult
    mutating func claimRescue(now: Date) throws -> Int {
        guard canClaimRescue(now: now) else { throw ClaimError.notAvailable }
        lastRescueDate = now
        credit(RewardTable.rescueAmount)
        return RewardTable.rescueAmount
    }

    mutating func completeTutorial(_ game: GameKind) -> Int {
        guard !completedTutorials.contains(game.rawValue) else { return 0 }
        completedTutorials.insert(game.rawValue)
        credit(RewardTable.tutorialReward)
        return RewardTable.tutorialReward
    }

    // MARK: - Missionen

    /// Stellt sicher, dass für den heutigen Tag Missionen vorhanden sind.
    /// Die Auswahl der Tagesmissionen erfolgt zufällig aus dem Pool – mit einer eigenen
    /// Zufallsquelle, die mit den Spielen nichts zu tun hat.
    mutating func refreshDailyMissions(now: Date, random: RandomSource, calendar: Calendar = .current) {
        if let date = missionsDate, calendar.isDate(date, inSameDayAs: now), !dailyMissions.isEmpty { return }
        var pool = RewardTable.missionPool
        random.shuffle(&pool)
        dailyMissions = pool.prefix(RewardTable.missionsPerDay).map {
            MissionProgress(missionID: $0.id, progress: 0, isClaimed: false)
        }
        missionsDate = now
    }

    func isMissionComplete(_ mission: MissionProgress) -> Bool {
        guard let def = RewardTable.mission(mission.missionID) else { return false }
        return mission.progress >= def.target
    }

    @discardableResult
    mutating func claimMission(_ id: String) throws -> [ProgressNotification] {
        guard let index = dailyMissions.firstIndex(where: { $0.missionID == id }),
              let def = RewardTable.mission(id) else { throw ClaimError.notAvailable }
        guard !dailyMissions[index].isClaimed else { throw ClaimError.alreadyClaimed }
        guard dailyMissions[index].progress >= def.target else { throw ClaimError.notAvailable }
        dailyMissions[index].isClaimed = true
        credit(def.rewardChips)
        return checkAchievements()
    }

    // MARK: - Erfolge

    func metricValue(_ metric: ProgressMetric) -> Int {
        switch metric {
        case .blackjackRounds: return stats.blackjackRounds
        case .blackjackHands: return stats.blackjackHands
        case .blackjackWins: return stats.blackjackWins
        case .blackjacks: return stats.blackjacks
        case .pokerHands: return stats.pokerHands
        case .pokerWins: return stats.pokerWins
        case .slotSpins: return stats.slotSpins
        case .slotWins: return stats.slotWins
        case .gamesPlayed: return stats.gamesPlayed
        case .roundsWon: return stats.roundsWon
        case .chipsWagered: return stats.totalWagered
        case .biggestWin: return stats.biggestWin
        case .peakChips: return stats.peakChips
        case .loginStreak: return loginStreak
        }
    }

    mutating func checkAchievements() -> [ProgressNotification] {
        var notes: [ProgressNotification] = []
        for def in RewardTable.achievements where !unlockedAchievements.contains(def.id) {
            if metricValue(def.metric) >= def.threshold {
                unlockedAchievements.insert(def.id)
                notes.append(.achievementUnlocked(def))
            }
        }
        return notes
    }

    @discardableResult
    mutating func claimAchievement(_ id: String) throws -> Int {
        guard let def = RewardTable.achievement(id), unlockedAchievements.contains(id) else { throw ClaimError.notAvailable }
        guard !claimedAchievements.contains(id) else { throw ClaimError.alreadyClaimed }
        claimedAchievements.insert(id)
        credit(def.rewardChips)
        return def.rewardChips
    }

    // MARK: - Spielereignisse

    /// Verbucht Statistik, Missionsfortschritt und Erfolge.
    /// Chips werden hier **nicht** bewegt – das passiert über die Wallet-Funktionen.
    /// Diese Daten fließen in keine Spiel-Engine zurück.
    mutating func record(_ event: GameEvent) -> [ProgressNotification] {
        var deltas: [ProgressMetric: Int] = [:]
        let stake: Int
        let net: Int

        switch event {
        case let .blackjackRound(s, payout, handsWon, pushes, blackjacks, hands):
            stake = s; net = payout - s
            stats.blackjackRounds += 1
            stats.blackjackHands += hands
            stats.blackjackWins += handsWon
            stats.blackjackPushes += pushes
            stats.blackjacks += blackjacks
            deltas[.blackjackRounds] = 1
            deltas[.blackjackHands] = hands
            deltas[.blackjackWins] = handsWon
            deltas[.blackjacks] = blackjacks
        case let .pokerHand(contributed, won):
            stake = contributed; net = won - contributed
            stats.pokerHands += 1
            deltas[.pokerHands] = 1
            if won > 0 {
                stats.pokerWins += 1
                deltas[.pokerWins] = 1
            }
        case let .slotSpin(bet, payout):
            stake = bet; net = payout - bet
            stats.slotSpins += 1
            deltas[.slotSpins] = 1
            if payout > 0 {
                stats.slotWins += 1
                deltas[.slotWins] = 1
            }
        }

        deltas[.gamesPlayed] = 1
        stats.totalWagered += stake
        deltas[.chipsWagered] = stake
        if net > 0 {
            stats.roundsWon += 1
            deltas[.roundsWon] = 1
            stats.totalWon += net
            stats.biggestWin = max(stats.biggestWin, net)
        } else if net < 0 {
            stats.totalLost += -net
        }

        var notes: [ProgressNotification] = []
        for i in dailyMissions.indices where !dailyMissions[i].isClaimed {
            guard let def = RewardTable.mission(dailyMissions[i].missionID), let delta = deltas[def.metric] else { continue }
            let wasComplete = dailyMissions[i].progress >= def.target
            dailyMissions[i].progress = min(def.target, dailyMissions[i].progress + delta)
            if !wasComplete && dailyMissions[i].progress >= def.target {
                notes.append(.missionCompleted(def))
            }
        }
        notes += checkAchievements()
        return notes
    }

    // MARK: - Hilfsfunktionen

    static func daysBetween(_ from: Date, _ to: Date, _ calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
