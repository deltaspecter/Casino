import XCTest
@testable import CasinoCore

final class SlotTests: XCTestCase {
    func testStripsContainConfiguredSymbolCounts() {
        for def in SlotCatalog.all {
            XCTAssertEqual(def.reelCount, 5)
            for strip in def.reelStrips {
                for symbol in strip { XCTAssertNotNil(def.symbols.first { $0.id == symbol }) }
            }
        }
    }

    func testLineEvaluationWithWilds() {
        let machine = SlotMachine(definition: SlotCatalog.crimsonSevens)
        XCTAssertEqual(machine.evaluateLine(["seven", "seven", "seven", "bar", "bar"])?.count, 3)
        XCTAssertEqual(machine.evaluateLine(["wild", "seven", "seven", "seven", "bar"])?.symbol, "seven")
        XCTAssertEqual(machine.evaluateLine(["wild", "seven", "seven", "seven", "bar"])?.count, 4)
        // Drei Wilds zahlen mehr als vier Kirschen → Wild-Kette gewinnt
        XCTAssertEqual(machine.evaluateLine(["wild", "wild", "wild", "cherry", "lemon"])?.symbol, "wild")
        XCTAssertEqual(machine.evaluateLine(["wild", "wild", "wild", "lemon", "bar"])?.multiplier, 125)
        XCTAssertNil(machine.evaluateLine(["cherry", "lemon", "cherry", "cherry", "cherry"]))
        XCTAssertNil(machine.evaluateLine(["scatter", "scatter", "scatter", "cherry", "cherry"]))
    }

    func testSpinIsConsistentWithStops() {
        let machine = SlotMachine(definition: SlotCatalog.midnightGems)
        let random = SeededRandomSource(seed: 5)
        for _ in 0..<1_000 {
            let r = machine.spin(lineBet: 2, random: random)
            XCTAssertEqual(r, machine.evaluate(stops: r.stops, lineBet: 2))
            XCTAssertEqual(r.totalBet, 20)
            XCTAssertEqual(r.grid.count, 5)
        }
    }

    /// Exakte RTP liegt in einem fairen Unterhaltungsbereich und wird durch Simulation bestätigt.
    func testRTPExactAndSimulated() {
        for def in SlotCatalog.all {
            let report = SlotMath.report(for: def)
            print("RTP \(def.name): \(String(format: "%.2f", report.rtp * 100)) % (Linien \(String(format: "%.2f", report.lineReturn * 100)), Scatter \(String(format: "%.2f", report.scatterReturn * 100)))")
            XCTAssertGreaterThan(report.rtp, 0.92, def.name)
            XCTAssertLessThan(report.rtp, 0.98, def.name)

            let machine = SlotMachine(definition: def)
            let random = SeededRandomSource(seed: 77)
            var bet = 0, won = 0
            for _ in 0..<300_000 {
                let r = machine.spin(lineBet: 1, random: random)
                bet += r.totalBet; won += r.totalPayout
            }
            let simulated = Double(won) / Double(bet)
            XCTAssertEqual(simulated, report.rtp, accuracy: 0.05, def.name)
        }
    }
}
