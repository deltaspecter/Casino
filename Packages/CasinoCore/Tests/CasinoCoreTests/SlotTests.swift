import XCTest
@testable import CasinoCore

final class SlotTests: XCTestCase {
    func testDefinitionsAreComplete() {
        for def in SlotCatalog.all {
            XCTAssertEqual(def.reelCount, 5)
            XCTAssertEqual(def.rows, 3)
            XCTAssertEqual(def.paylines.count, 10)
            XCTAssertTrue(def.paylines.allSatisfy { $0.count == 5 && $0.allSatisfy { (0..<3).contains($0) } })
            XCTAssertEqual(def.symbols.filter { $0.kind == .wild }.count, 1)
            XCTAssertEqual(def.symbols.filter { $0.kind == .scatter }.count, 1)
            for reel in 0..<def.reelCount {
                for symbol in def.reelStrips[reel] { XCTAssertNotNil(def.symbols.first { $0.id == symbol }) }
                let total = def.symbols.reduce(0.0) { $0 + def.probability(of: $1.id, onReel: reel) }
                XCTAssertEqual(total, 1, accuracy: 1e-9, "Wahrscheinlichkeiten je Walze summieren sich zu 1")
            }
        }
    }

    /// Jede Symbolkombination (3, 4, 5 gleiche) zahlt genau den Wert der Gewinntabelle.
    func testEveryWinningCombinationPaysTable() {
        for def in SlotCatalog.all {
            let machine = SlotMachine(definition: def)
            let regular = def.symbols.filter { $0.kind == .regular }
            for symbol in regular {
                let blocker = regular.first { $0.id != symbol.id }!.id
                for n in 3...5 {
                    let line = Array(repeating: symbol.id, count: n) + Array(repeating: blocker, count: 5 - n)
                    let win = machine.evaluateLine(line)
                    XCTAssertEqual(win?.symbol, symbol.id, "\(def.name) \(symbol.id) ×\(n)")
                    XCTAssertEqual(win?.count, n)
                    XCTAssertEqual(win?.multiplier, symbol.payout(for: n))
                }
                XCTAssertNil(machine.evaluateLine([symbol.id, symbol.id, blocker, blocker, blocker]), "Zwei gleiche zahlen nicht")
            }
            let wild = def.symbols.first { $0.kind == .wild }!
            let scatter = def.symbols.first { $0.kind == .scatter }!
            for n in 3...5 {
                let line = Array(repeating: wild.id, count: n) + Array(repeating: scatter.id, count: 5 - n)
                XCTAssertEqual(machine.evaluateLine(line)?.multiplier, wild.payout(for: n))
            }
        }
    }

    func testWildSubstitutionAndNoWins() {
        let machine = SlotMachine(definition: SlotCatalog.crimsonSevens)
        XCTAssertEqual(machine.evaluateLine(["wild", "seven", "seven", "seven", "bar"])?.symbol, "seven")
        XCTAssertEqual(machine.evaluateLine(["wild", "seven", "seven", "seven", "bar"])?.count, 4)
        XCTAssertEqual(machine.evaluateLine(["seven", "wild", "seven", "bar", "bar"])?.count, 3)
        XCTAssertEqual(machine.evaluateLine(["wild", "wild", "wild", "cherry", "lemon"])?.symbol, "wild",
                       "Höherer Gewinn (Wild-Kette) wird gezahlt")
        XCTAssertNil(machine.evaluateLine(["cherry", "lemon", "cherry", "cherry", "cherry"]), "Nur von links")
        XCTAssertNil(machine.evaluateLine(["scatter", "scatter", "scatter", "cherry", "cherry"]), "Scatter zahlt nicht auf Linien")
        XCTAssertNil(machine.evaluateLine(["wild", "scatter", "seven", "seven", "seven"]), "Wild ersetzt keinen Scatter")
    }

    func testScatterPaysAnywhere() {
        for def in SlotCatalog.all {
            let machine = SlotMachine(definition: def)
            let scatter = def.symbols.first { $0.kind == .scatter }!
            var withScatter: [Int] = [], without: [Int] = []
            for reel in 0..<5 {
                let n = def.reelStrips[reel].count
                withScatter.append((0..<n).first { machine.window(reel: reel, stop: $0).filter { $0 == scatter.id }.count == 1 }!)
                without.append((0..<n).first { !machine.window(reel: reel, stop: $0).contains(scatter.id) }!)
            }
            for k in 0...5 {
                let stops = (0..<5).map { $0 < k ? withScatter[$0] : without[$0] }
                let result = machine.evaluate(stops: stops, lineBet: 2)
                XCTAssertEqual(result.scatterCount, k)
                XCTAssertEqual(result.scatterPayout, scatter.payout(for: k) * result.totalBet)
            }
        }
    }

    func testPayoutScalesLinearlyWithBet() {
        let machine = SlotMachine(definition: SlotCatalog.dragonFortune)
        let random = SeededRandomSource(seed: 12)
        for _ in 0..<2_000 {
            let r1 = machine.spin(lineBet: 1, random: random)
            let r7 = machine.evaluate(stops: r1.stops, lineBet: 7)
            XCTAssertEqual(r7.totalPayout, r1.totalPayout * 7)
            XCTAssertEqual(r7.totalBet, r1.totalBet * 7)
        }
    }

    func testNoWinSpinsExistAndPayZero() {
        let machine = SlotMachine(definition: SlotCatalog.midnightGems)
        let random = SeededRandomSource(seed: 5)
        var losses = 0
        for _ in 0..<1_000 {
            let r = machine.spin(lineBet: 2, random: random)
            XCTAssertEqual(r, machine.evaluate(stops: r.stops, lineBet: 2))
            if !r.isWin {
                losses += 1
                XCTAssertEqual(r.totalPayout, 0)
                XCTAssertTrue(r.lineWins.isEmpty)
            }
        }
        XCTAssertGreaterThan(losses, 0)
    }

    func testLowBalanceCannotSpin() throws {
        var profile = PlayerProfile()
        try profile.debit(profile.chips - 5)
        let totalBet = SlotCatalog.crimsonSevens.lineBetOptions[0] * 10
        XCTAssertThrowsError(try profile.debit(totalBet))
        XCTAssertEqual(profile.chips, 5, "Kontostand bleibt unverändert und nie negativ")
    }

    func testRTPExactAndSimulated() {
        for def in SlotCatalog.all {
            let report = SlotMath.report(for: def)
            print("RTP \(def.name): \(String(format: "%.2f", report.rtp * 100)) %")
            XCTAssertGreaterThan(report.rtp, 0.92, def.name)
            XCTAssertLessThan(report.rtp, 0.98, def.name)

            let machine = SlotMachine(definition: def)
            let random = SeededRandomSource(seed: 77)
            var bet = 0, won = 0
            for _ in 0..<300_000 {
                let r = machine.spin(lineBet: 1, random: random)
                bet += r.totalBet; won += r.totalPayout
            }
            XCTAssertEqual(Double(won) / Double(bet), report.rtp, accuracy: 0.05, def.name)
        }
    }
}
