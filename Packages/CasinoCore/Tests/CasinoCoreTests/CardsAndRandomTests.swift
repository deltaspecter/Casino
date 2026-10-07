import XCTest
@testable import CasinoCore

final class CardsAndRandomTests: XCTestCase {
    func testShoeContainsEveryCardExactlyOncePerDeck() {
        let shoe = Shoe(deckCount: 6, random: SeededRandomSource(seed: 1))
        XCTAssertEqual(shoe.remaining, 312)
        XCTAssertEqual(Set(shoe.cards.map(\.id)).count, 312)
        for rank in Rank.allCases {
            XCTAssertEqual(shoe.cards.filter { $0.rank == rank }.count, 24)
        }
    }

    func testShoeDrawsWithoutDuplicates() {
        let random = SeededRandomSource(seed: 2)
        var shoe = Shoe(deckCount: 1, random: random)
        let drawn = (0..<52).map { _ in shoe.draw(random: random) }
        XCTAssertEqual(Set(drawn.map(\.id)).count, 52)
        XCTAssertEqual(shoe.remaining, 0)
    }

    func testShuffleIsUniformEnough() {
        // Jede Position eines 4er-Arrays sollte jedes Element ~25 % der Zeit enthalten.
        let random = SeededRandomSource(seed: 3)
        var counts = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        let trials = 40_000
        for _ in 0..<trials {
            var a = [0, 1, 2, 3]
            random.shuffle(&a)
            for (pos, v) in a.enumerated() { counts[pos][v] += 1 }
        }
        for row in counts {
            for c in row {
                XCTAssertEqual(Double(c) / Double(trials), 0.25, accuracy: 0.01)
            }
        }
    }

    func testSystemRandomSourceProducesValuesInRange() {
        let random = SystemRandomSource()
        for _ in 0..<1_000 {
            let v = random.uniform(7)
            XCTAssertTrue((0..<7).contains(v))
        }
    }
}
