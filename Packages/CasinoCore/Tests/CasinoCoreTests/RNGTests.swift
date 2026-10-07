import XCTest
@testable import CasinoCore

/// Prüft die Zufallslogik: korrektes Mischen, keine Dubletten, Vielfalt
/// und vor allem Unabhängigkeit von Kontostand, Einsatz, Verlauf, Missionen und Erfolgen.
final class RNGTests: XCTestCase {
    /// Chi-Quadrat-Statistik für beobachtete Häufigkeiten bei Gleichverteilung.
    private func chiSquare(_ counts: [Int]) -> Double {
        let total = Double(counts.reduce(0, +))
        let expected = total / Double(counts.count)
        return counts.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
    }

    func testShuffleIsUniformOverAllPositions() {
        // Position des Pik-Ass in 52.000 Mischungen: Chi² mit 51 Freiheitsgraden (99,9 %-Grenze ≈ 87)
        let random = SeededRandomSource(seed: 101)
        var counts = Array(repeating: 0, count: 52)
        let target = Card(.ace, .spades)
        for _ in 0..<52_000 {
            var deck = Card.standardDeck()
            random.shuffle(&deck)
            counts[deck.firstIndex(of: target)!] += 1
        }
        XCTAssertLessThan(chiSquare(counts), 87)
    }

    func testShuffleKeepsEveryCardExactlyOnce() {
        let random = SystemRandomSource()
        for _ in 0..<1_000 {
            var deck = Card.standardDeck()
            random.shuffle(&deck)
            XCTAssertEqual(deck.count, 52)
            XCTAssertEqual(Set(deck), Set(Card.standardDeck()))
        }
    }

    func testDifferentResultsOccur() {
        let random = SystemRandomSource()
        var orders = Set<[Int]>()
        for _ in 0..<500 {
            var deck = Card.standardDeck()
            random.shuffle(&deck)
            orders.insert(deck.map(\.id))
        }
        XCTAssertEqual(orders.count, 500, "Mischungen wiederholen sich nicht")

        let machine = SlotMachine(definition: SlotCatalog.crimsonSevens)
        let stops = Set((0..<500).map { _ in machine.spin(lineBet: 1, random: random).stops })
        XCTAssertGreaterThan(stops.count, 450)
    }

    func testSlotReelStopsAreUniform() {
        let def = SlotCatalog.dragonFortune
        let machine = SlotMachine(definition: def)
        let random = SeededRandomSource(seed: 31)
        var counts = def.reelStrips.map { Array(repeating: 0, count: $0.count) }
        for _ in 0..<66_000 {
            let r = machine.spin(lineBet: 1, random: random)
            for (reel, stop) in r.stops.enumerated() { counts[reel][stop] += 1 }
        }
        for reel in counts {
            // 32 Freiheitsgrade (Streifenlänge 33) → 99,9 %-Grenze ≈ 62
            XCTAssertLessThan(chiSquare(reel), 62)
        }
    }

    /// Die Gewinnwahrscheinlichkeit nach einem Gewinn entspricht der nach einem Verlust.
    func testSlotOutcomeIndependentOfPreviousOutcome() {
        let machine = SlotMachine(definition: SlotCatalog.crimsonSevens)
        let random = SeededRandomSource(seed: 44)
        var afterWin = (wins: 0, total: 0), afterLoss = (wins: 0, total: 0)
        var previousWin = false
        for _ in 0..<300_000 {
            let win = machine.spin(lineBet: 1, random: random).isWin
            if previousWin { afterWin.total += 1; if win { afterWin.wins += 1 } }
            else { afterLoss.total += 1; if win { afterLoss.wins += 1 } }
            previousWin = win
        }
        let p1 = Double(afterWin.wins) / Double(afterWin.total)
        let p2 = Double(afterLoss.wins) / Double(afterLoss.total)
        XCTAssertEqual(p1, p2, accuracy: 0.01)
    }

    func testBlackjackOutcomeIndependentOfPreviousOutcome() throws {
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 45))
        var afterWin = (wins: 0, total: 0), afterLoss = (wins: 0, total: 0)
        var previousNet = 0
        for _ in 0..<60_000 {
            try engine.startRound(bet: 10)
            while engine.phase == .playerTurn {
                try engine.perform(engine.activeHand!.value.total >= 17 ? .stand : .hit)
            }
            let net = engine.results.reduce(0) { $0 + $1.net }
            if previousNet > 0 { afterWin.total += 1; if net > 0 { afterWin.wins += 1 } }
            else if previousNet < 0 { afterLoss.total += 1; if net > 0 { afterLoss.wins += 1 } }
            previousNet = net
        }
        XCTAssertEqual(Double(afterWin.wins) / Double(afterWin.total),
                       Double(afterLoss.wins) / Double(afterLoss.total), accuracy: 0.02)
    }

    /// Einsatzhöhe (und damit Kontostand) hat keinen Einfluss auf die Karten.
    func testBlackjackCardsIndependentOfStake() throws {
        func run(bet: Int) throws -> [[Card]] {
            let engine = BlackjackEngine(rules: BlackjackRules(minBet: 1, maxBet: 1_000_000), random: SeededRandomSource(seed: 77))
            var rounds: [[Card]] = []
            for _ in 0..<500 {
                try engine.startRound(bet: bet)
                while engine.phase == .playerTurn {
                    try engine.perform(engine.activeHand!.value.total >= 17 ? .stand : .hit)
                }
                rounds.append(engine.hands.flatMap(\.cards) + engine.dealerCards)
            }
            return rounds
        }
        XCTAssertEqual(try run(bet: 1), try run(bet: 999_999))
    }

    func testSlotResultsIndependentOfStake() {
        let machine = SlotMachine(definition: SlotCatalog.midnightGems)
        let a = SeededRandomSource(seed: 8), b = SeededRandomSource(seed: 8)
        for _ in 0..<2_000 {
            XCTAssertEqual(machine.spin(lineBet: 1, random: a).stops, machine.spin(lineBet: 100, random: b).stops)
        }
    }

    func testPokerDealIndependentOfStacks() throws {
        func deal(stacks: [Int]) throws -> [Card] {
            let seats = stacks.enumerated().map { PokerSeat(id: $0.offset, name: "P", isHuman: false, style: .rock, stack: $0.element) }
            let engine = HoldemEngine(seats: seats, smallBlind: 5, bigBlind: 10, random: SeededRandomSource(seed: 3))
            try engine.startHand()
            return engine.seats.flatMap(\.holeCards)
        }
        XCTAssertEqual(try deal(stacks: [20, 20, 20]), try deal(stacks: [1_000_000, 50, 999]))
    }

    /// Missionen, Erfolge, Daily Reward und Statistik greifen nicht auf die Spiel-Zufallsquelle zu:
    /// Eine Spin-Folge bleibt identisch, egal was dazwischen im Profil passiert.
    func testProfileActivityDoesNotTouchGameRNG() throws {
        let machine = SlotMachine(definition: SlotCatalog.crimsonSevens)
        let plain = SeededRandomSource(seed: 55)
        let busy = SeededRandomSource(seed: 55)
        let missionRandom = SeededRandomSource(seed: 999) // eigene Quelle wie in der App
        var profile = PlayerProfile()
        let now = Date()
        for i in 0..<1_000 {
            let expected = machine.spin(lineBet: 1, random: plain)
            profile.refreshDailyMissions(now: now.addingTimeInterval(Double(i) * 3_600), random: missionRandom)
            _ = try? profile.claimDailyReward(now: now.addingTimeInterval(Double(i) * 86_400))
            for m in profile.dailyMissions { _ = try? profile.claimMission(m.missionID) }
            for a in profile.unlockedAchievements { _ = try? profile.claimAchievement(a) }
            let actual = machine.spin(lineBet: 1, random: busy)
            XCTAssertEqual(actual, expected)
            _ = profile.record(.slotSpin(bet: actual.totalBet, payout: actual.totalPayout))
        }
    }

    func testSystemRandomSourceRangeAndSpread() {
        let random = SystemRandomSource()
        var seen = Set<Int>()
        for _ in 0..<2_000 {
            let v = random.uniform(7)
            XCTAssertTrue((0..<7).contains(v))
            seen.insert(v)
        }
        XCTAssertEqual(seen.count, 7)
    }
}
