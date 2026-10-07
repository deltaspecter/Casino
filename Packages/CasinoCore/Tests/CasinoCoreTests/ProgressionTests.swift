import XCTest
@testable import CasinoCore

final class ProgressionTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func testStartingChips() {
        XCTAssertEqual(PlayerProfile().chips, 10_000)
    }

    func testWallet() throws {
        var p = PlayerProfile()
        try p.debit(1_000)
        XCTAssertEqual(p.chips, 9_000)
        XCTAssertThrowsError(try p.debit(20_000))
        XCTAssertThrowsError(try p.debit(0))
        p.credit(500)
        XCTAssertEqual(p.chips, 9_500)
    }

    func testTableEscrow() throws {
        var p = PlayerProfile()
        try p.moveToTable(1_000)
        XCTAssertEqual(p.chips, 9_000)
        XCTAssertEqual(p.tableEscrow, 1_000)
        p.releaseFromTable(stake: 1_000, payout: 2_000)
        XCTAssertEqual(p.chips, 11_000)
        XCTAssertEqual(p.tableEscrow, 0)

        try p.moveToTable(500)
        XCTAssertEqual(p.refundTableEscrow(), 500)
        XCTAssertEqual(p.chips, 11_000)
    }

    func testLoginStreak() throws {
        var p = PlayerProfile()
        XCTAssertEqual(try p.claimLoginBonus(now: date(1), calendar: calendar).streakDay, 1)
        XCTAssertNil(p.loginBonusOffer(now: date(1, hour: 23), calendar: calendar))
        XCTAssertEqual(try p.claimLoginBonus(now: date(2, hour: 0), calendar: calendar).streakDay, 2)
        XCTAssertEqual(try p.claimLoginBonus(now: date(3), calendar: calendar).amount, 1_000)
        // Tag ausgelassen → Serie beginnt neu
        XCTAssertEqual(try p.claimLoginBonus(now: date(5), calendar: calendar).streakDay, 1)
    }

    func testDailyRewardOncePerDay() throws {
        var p = PlayerProfile()
        XCTAssertEqual(try p.claimDailyReward(now: date(1), calendar: calendar), RewardTable.dailyReward)
        XCTAssertThrowsError(try p.claimDailyReward(now: date(1, hour: 20), calendar: calendar))
        XCTAssertNoThrow(try p.claimDailyReward(now: date(2, hour: 1), calendar: calendar))
    }

    func testStatisticsTrackWinsAndLosses() {
        var p = PlayerProfile()
        _ = p.record(.blackjackRound(stake: 100, payout: 250, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1))
        _ = p.record(.blackjackRound(stake: 200, payout: 200, handsWon: 0, pushes: 1, blackjacks: 0, hands: 2))
        _ = p.record(.pokerHand(contributed: 300, won: 0))
        _ = p.record(.slotSpin(bet: 10, payout: 50))
        _ = p.record(.slotSpin(bet: 10, payout: 0))
        XCTAssertEqual(p.stats.blackjackRounds, 2)
        XCTAssertEqual(p.stats.blackjackHands, 3)
        XCTAssertEqual(p.stats.blackjackPushes, 1)
        XCTAssertEqual(p.stats.pokerHands, 1)
        XCTAssertEqual(p.stats.pokerWins, 0)
        XCTAssertEqual(p.stats.slotSpins, 2)
        XCTAssertEqual(p.stats.slotWins, 1)
        XCTAssertEqual(p.stats.gamesPlayed, 5)
        XCTAssertEqual(p.stats.roundsWon, 2)
        XCTAssertEqual(p.stats.totalWon, 190)
        XCTAssertEqual(p.stats.totalLost, 310)
        XCTAssertEqual(p.stats.biggestWin, 150)
        XCTAssertEqual(p.stats.totalWagered, 620)
        XCTAssertEqual(p.chips, PlayerProfile.startingChips, "Statistik bewegt keine Chips")
    }

    func testMissionsProgressAndClaim() throws {
        var p = PlayerProfile()
        p.refreshDailyMissions(now: date(1), random: SeededRandomSource(seed: 1), calendar: calendar)
        XCTAssertEqual(p.dailyMissions.count, 3)

        // Alle Spiele so lange spielen, bis jede Mission erfüllt ist
        for _ in 0..<40 {
            _ = p.record(.blackjackRound(stake: 600, payout: 1_500, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1))
            _ = p.record(.pokerHand(contributed: 600, won: 1_000))
            _ = p.record(.slotSpin(bet: 600, payout: 100))
        }
        for m in p.dailyMissions {
            XCTAssertTrue(p.isMissionComplete(m))
            XCTAssertNoThrow(try p.claimMission(m.missionID))
            XCTAssertThrowsError(try p.claimMission(m.missionID))
        }
        // Gleicher Tag → gleiche Missionen
        let ids = p.dailyMissions.map(\.missionID)
        p.refreshDailyMissions(now: date(1, hour: 22), random: SeededRandomSource(seed: 2), calendar: calendar)
        XCTAssertEqual(p.dailyMissions.map(\.missionID), ids)
    }

    func testAchievementsUnlockAndClaimOnce() throws {
        var p = PlayerProfile()
        let notes = p.record(.blackjackRound(stake: 100, payout: 250, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1))
        XCTAssertTrue(notes.contains(.achievementUnlocked(RewardTable.achievement("natural")!)))
        XCTAssertTrue(notes.contains(.achievementUnlocked(RewardTable.achievement("first-win")!)))
        XCTAssertEqual(try p.claimAchievement("natural"), 500)
        XCTAssertThrowsError(try p.claimAchievement("natural"))
        XCTAssertThrowsError(try p.claimAchievement("high-roller"))
    }

    func testTutorialRewardOnlyOnce() {
        var p = PlayerProfile()
        XCTAssertEqual(p.completeTutorial(.slots), 1_000)
        XCTAssertEqual(p.completeTutorial(.slots), 0)
    }

    func testRescue() throws {
        var p = PlayerProfile()
        XCTAssertFalse(p.canClaimRescue(now: date(1)))
        try p.debit(p.chips - 50)
        XCTAssertTrue(p.canClaimRescue(now: date(1)))
        try p.claimRescue(now: date(1))
        try p.debit(p.chips - 10)
        XCTAssertFalse(p.canClaimRescue(now: date(1).addingTimeInterval(60)))
        XCTAssertTrue(p.canClaimRescue(now: date(1).addingTimeInterval(3_600)))
    }

    func testPersistenceRoundTripAndCorruptionRecovery() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: dir.appendingPathComponent("profile.json"))

        var p = PlayerProfile()
        p.credit(1_234)
        _ = p.completeTutorial(.poker)
        try store.save(p)
        let (loaded, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(loaded.chips, p.chips)
        XCTAssertEqual(loaded.completedTutorials, p.completedTutorials)

        try Data("kaputt".utf8).write(to: store.fileURL)
        let (fresh, outcome2) = store.load()
        XCTAssertEqual(fresh.chips, PlayerProfile.startingChips)
        if case .recoveredFromCorruption = outcome2 {} else { XCTFail("Erwartete Wiederherstellung") }
    }

    func testLoadsOlderOrIncompleteSaveFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: dir.appendingPathComponent("profile.json"))

        // Alte Version mit XP/Level-Feldern und unbekannter Mission → wird bereinigt übernommen
        let old = """
        {"version":1,"chips":12345,"xp":300,"level":4,"displayName":"Kim",
         "dailyMissions":[{"missionID":"gibt-es-nicht","progress":2,"isClaimed":false}],
         "unlockedAchievements":["natural","unbekannt"],"claimedAchievements":["unbekannt"],
         "stats":{"slotSpins":7}}
        """
        try Data(old.utf8).write(to: store.fileURL)
        let (p, outcome) = store.load()
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(p.chips, 12_345)
        XCTAssertEqual(p.displayName, "Kim")
        XCTAssertEqual(p.stats.slotSpins, 7)
        XCTAssertTrue(p.dailyMissions.isEmpty)
        XCTAssertEqual(p.unlockedAchievements, ["natural"])
        XCTAssertTrue(p.claimedAchievements.isEmpty)

        // Negativer Kontostand (manipulierte Datei) wird auf 0 korrigiert
        try Data(#"{"chips":-500,"tableEscrow":-3}"#.utf8).write(to: store.fileURL)
        let (fixed, _) = store.load()
        XCTAssertEqual(fixed.chips, 0)
        XCTAssertEqual(fixed.tableEscrow, 0)

        // Datei ohne Kontostand ist unbrauchbar → neues Profil
        try Data(#"{"displayName":"X"}"#.utf8).write(to: store.fileURL)
        let (fresh, outcome3) = store.load()
        XCTAssertEqual(fresh.chips, PlayerProfile.startingChips)
        if case .recoveredFromCorruption = outcome3 {} else { XCTFail("Erwartete Wiederherstellung") }
    }

    func testBalanceNeverNegative() throws {
        var p = PlayerProfile()
        XCTAssertThrowsError(try p.debit(-10))
        XCTAssertThrowsError(try p.moveToTable(p.chips + 1))
        try p.moveToTable(p.chips)
        XCTAssertEqual(p.chips, 0)
        XCTAssertThrowsError(try p.debit(1))
        p.credit(-100)
        XCTAssertEqual(p.chips, 0)
        p.releaseFromTable(stake: 999_999, payout: 0)
        XCTAssertEqual(p.tableEscrow, 0)
        XCTAssertGreaterThanOrEqual(p.chips, 0)
    }
}
