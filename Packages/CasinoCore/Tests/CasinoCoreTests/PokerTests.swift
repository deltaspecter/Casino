import XCTest
@testable import CasinoCore

final class PokerTests: XCTestCase {
    private func cards(_ s: String) -> [Card] {
        // Format: "As Kd 10h 2c"
        s.split(separator: " ").map { token in
            let suitChar = token.last!
            let rankStr = String(token.dropLast())
            let suit: Suit = ["c": .clubs, "d": .diamonds, "h": .hearts, "s": .spades][suitChar]!
            let rank = Rank.allCases.first { $0.label == rankStr }!
            return Card(rank, suit)
        }
    }

    func testCategories() {
        XCTAssertEqual(HandEvaluator.bestHand(cards("As Ks Qs Js 10s 2d 3c")).name, "Royal Flush")
        XCTAssertEqual(HandEvaluator.bestHand(cards("5s 4s 3s 2s As Kd Kc")).category, .straightFlush)
        XCTAssertEqual(HandEvaluator.bestHand(cards("9s 9d 9h 9c 2s 3d 4c")).category, .fourOfAKind)
        XCTAssertEqual(HandEvaluator.bestHand(cards("9s 9d 9h 2c 2s 3d 4c")).category, .fullHouse)
        XCTAssertEqual(HandEvaluator.bestHand(cards("As 9s 7s 4s 2s 3d 4c")).category, .flush)
        XCTAssertEqual(HandEvaluator.bestHand(cards("As 2d 3h 4c 5s Kd Qc")).category, .straight)
        XCTAssertEqual(HandEvaluator.bestHand(cards("7s 7d 7h Kc 2s 3d 9c")).category, .threeOfAKind)
        XCTAssertEqual(HandEvaluator.bestHand(cards("7s 7d Kh Kc 2s 3d 9c")).category, .twoPair)
        XCTAssertEqual(HandEvaluator.bestHand(cards("7s 7d Ah Kc 2s 3d 9c")).category, .onePair)
        XCTAssertEqual(HandEvaluator.bestHand(cards("7s 8d Ah Kc 2s 3d 10c")).category, .highCard)
    }

    func testComparisons() {
        let wheel = HandEvaluator.evaluate5(cards("As 2d 3h 4c 5s"))
        let sixHigh = HandEvaluator.evaluate5(cards("2s 3d 4h 5c 6s"))
        XCTAssertLessThan(wheel, sixHigh)

        let pairAcesKing = HandEvaluator.evaluate5(cards("As Ad Kh 4c 3s"))
        let pairAcesQueen = HandEvaluator.evaluate5(cards("Ac Ah Qh 4d 3d"))
        XCTAssertGreaterThan(pairAcesKing, pairAcesQueen)

        let split1 = HandEvaluator.evaluate5(cards("As Kd Qh Jc 9s"))
        let split2 = HandEvaluator.evaluate5(cards("Ad Ks Qc Jh 9d"))
        XCTAssertEqual(split1, split2)

        let twoPairHigh = HandEvaluator.evaluate5(cards("Ks Kd 2h 2c As"))
        let twoPairLow = HandEvaluator.evaluate5(cards("Qs Qd Jh Jc As"))
        XCTAssertGreaterThan(twoPairHigh, twoPairLow)
    }

    private func makeEngine(stacks: [Int], seed: UInt64) -> HoldemEngine {
        let seats = stacks.enumerated().map { i, stack in
            PokerSeat(id: i, name: "P\(i)", isHuman: i == 0, style: i == 0 ? nil : PokerStyle.allCases[i % 4], stack: stack)
        }
        return HoldemEngine(seats: seats, smallBlind: 5, bigBlind: 10, random: SeededRandomSource(seed: seed))
    }

    func testChipsAreConservedOverManyHands() throws {
        let random = SeededRandomSource(seed: 99)
        let engine = makeEngine(stacks: [1_000, 400, 1_500, 250, 800, 2_000], seed: 5)
        let total = engine.seats.reduce(0) { $0 + $1.stack }

        for _ in 0..<2_000 {
            if engine.seats.filter({ $0.stack > 0 }).count < 2 {
                for i in engine.seats.indices where engine.seats[i].stack == 0 { try engine.setStack(500, forSeatAt: i) }
            }
            let before = engine.seats.reduce(0) { $0 + $1.stack }
            try engine.startHand()
            var guardCounter = 0
            while engine.isHandInProgress, let idx = engine.currentIndex {
                guardCounter += 1
                XCTAssertLessThan(guardCounter, 500, "Hand endet nicht")
                let legal = engine.legalActions(forSeatAt: idx)!
                var options: [PokerAction] = [.fold, .allIn]
                options.append(legal.canCheck ? .check : .call)
                if legal.canRaise { options.append(.raise(to: legal.minRaiseTo)) }
                try engine.apply(random.pick(options)!, forSeatAt: idx)
            }
            let after = engine.seats.reduce(0) { $0 + $1.stack }
            XCTAssertEqual(before, after, "Chips müssen erhalten bleiben")
            XCTAssertTrue(engine.seats.allSatisfy { $0.stack >= 0 })
            if engine.street == .showdown && !engine.lastShowdown.isEmpty {
                XCTAssertEqual(engine.community.count, 5)
            }
        }
        _ = total
    }

    func testSidePots() throws {
        let engine = makeEngine(stacks: [100, 300, 300], seed: 1)
        try engine.startHand()
        // Alle gehen all-in, egal wer beginnt
        while engine.isHandInProgress, let idx = engine.currentIndex {
            let legal = engine.legalActions(forSeatAt: idx)!
            try engine.apply(legal.canRaise ? .allIn : .call, forSeatAt: idx)
        }
        XCTAssertEqual(engine.seats.reduce(0) { $0 + $1.stack }, 700)
        let awardedPots = Set(engine.lastAwards.map(\.potIndex))
        XCTAssertTrue(awardedPots.isSubset(of: [0, 1]))
        // Der Short-Stack kann höchstens den Hauptpot (3 × 100) gewinnen
        let shortWin = engine.lastAwards.filter { $0.seatID == 0 }.reduce(0) { $0 + $1.amount }
        XCTAssertLessThanOrEqual(shortWin, 300)
    }

    func testAIProducesLegalActions() throws {
        let random = SeededRandomSource(seed: 3)
        let engine = makeEngine(stacks: [1_000, 1_000, 1_000, 1_000], seed: 8)
        for _ in 0..<40 {
            for i in engine.seats.indices where engine.seats[i].stack == 0 { try engine.setStack(1_000, forSeatAt: i) }
            try engine.startHand()
            while engine.isHandInProgress, let idx = engine.currentIndex {
                let ctx = PokerAIContext(engine: engine, seatIndex: idx)
                let style = engine.seats[idx].style ?? .shark
                let action = PokerAI.decide(context: ctx, style: style, random: random)
                XCTAssertNoThrow(try engine.apply(action, forSeatAt: idx), "\(action)")
            }
        }
    }

    func testEquityEstimateIsSensible() {
        let random = SeededRandomSource(seed: 4)
        let aces = PokerAI.estimateEquity(hole: cards("As Ah"), community: [], opponents: 1, iterations: 2_000, random: random)
        let junk = PokerAI.estimateEquity(hole: cards("7c 2d"), community: [], opponents: 1, iterations: 2_000, random: random)
        XCTAssertEqual(aces, 0.85, accuracy: 0.04)
        XCTAssertEqual(junk, 0.35, accuracy: 0.05)
    }
}
