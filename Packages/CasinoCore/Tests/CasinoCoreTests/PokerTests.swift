import XCTest
@testable import CasinoCore

final class PokerTests: XCTestCase {
    /// Format: "As Kd 10h 2c"
    private func cards(_ s: String) -> [Card] {
        s.split(separator: " ").map { token in
            let suit: Suit = ["c": .clubs, "d": .diamonds, "h": .hearts, "s": .spades][token.last!]!
            let rank = Rank.allCases.first { $0.label == String(token.dropLast()) }!
            return Card(rank, suit)
        }
    }

    private func best(_ s: String) -> PokerHandRank { HandEvaluator.bestHand(cards(s)) }

    // MARK: - Handwertung

    func testAllCategories() {
        XCTAssertEqual(best("As Ks Qs Js 10s 2d 3c").name, "Royal Flush")
        XCTAssertEqual(best("9h 8h 7h 6h 5h Kd Kc").category, .straightFlush)
        XCTAssertEqual(best("5s 4s 3s 2s As Kd Kc").category, .straightFlush)
        XCTAssertEqual(best("9s 9d 9h 9c 2s 3d 4c").category, .fourOfAKind)
        XCTAssertEqual(best("9s 9d 9h 2c 2s 3d 4c").category, .fullHouse)
        XCTAssertEqual(best("As 9s 7s 4s 2s 3d 4c").category, .flush)
        XCTAssertEqual(best("As 2d 3h 4c 5s Kd Qc").category, .straight)
        XCTAssertEqual(best("10s Jd Qh Kc As 2d 2c").category, .straight)
        XCTAssertEqual(best("7s 7d 7h Kc 2s 3d 9c").category, .threeOfAKind)
        XCTAssertEqual(best("7s 7d Kh Kc 2s 3d 9c").category, .twoPair)
        XCTAssertEqual(best("7s 7d Ah Kc 2s 3d 9c").category, .onePair)
        XCTAssertEqual(best("7s 8d Ah Kc 2s 3d 10c").category, .highCard)
    }

    func testCategoryOrderIsOfficialRanking() {
        let ascending = [
            "7s 8d Ah Kc 2s", "7s 7d Ah Kc 2s", "7s 7d Kh Kc 2s", "7s 7d 7h Kc 2s", "6s 7d 8h 9c 10s",
            "2h 7h 9h Jh Kh", "7s 7d 7h Kc Ks", "7s 7d 7h 7c Ks", "5d 6d 7d 8d 9d", "10c Jc Qc Kc Ac"
        ].map { HandEvaluator.evaluate5(cards($0)) }
        for (lower, higher) in zip(ascending, ascending.dropFirst()) {
            XCTAssertLessThan(lower, higher, "\(lower.name) < \(higher.name)")
        }
        XCTAssertEqual(ascending.last?.name, "Royal Flush")
    }

    func testTiebreakers() {
        let e5 = { HandEvaluator.evaluate5(self.cards($0)) }
        XCTAssertLessThan(e5("As 2d 3h 4c 5s"), e5("2s 3d 4h 5c 6s"), "Wheel ist die niedrigste Straße")
        XCTAssertGreaterThan(e5("As Ad Kh 4c 3s"), e5("Ac Ah Qh 4d 3d"), "Kicker entscheidet")
        XCTAssertGreaterThan(e5("Ks Kd 2h 2c As"), e5("Qs Qd Jh Jc As"), "Höheres oberes Paar")
        XCTAssertGreaterThan(e5("Ks Kd 3h 3c 2s"), e5("Kh Kc 2h 2d As"), "Zweites Paar vor Kicker")
        XCTAssertGreaterThan(e5("3s 3d 3h 2c 2s"), e5("2s 2d 2h Ac As"), "Full House: Drilling zählt zuerst")
        XCTAssertGreaterThan(e5("Ah 9h 7h 4h 3h"), e5("Ad 9d 7d 4d 2d"), "Flush: alle Karten vergleichen")
        XCTAssertEqual(e5("As Kd Qh Jc 9s"), e5("Ad Ks Qc Jh 9d"), "Gleiche Werte → Gleichstand")
        XCTAssertGreaterThan(e5("9s 9d 9h 9c As"), e5("9s 9d 9h 9c Ks"), "Vierling-Kicker")
    }

    // MARK: - Engine-Szenarien

    private func makeEngine(stacks: [Int], seed: UInt64 = 1) -> HoldemEngine {
        let seats = stacks.enumerated().map { i, stack in
            PokerSeat(id: i, name: "P\(i)", isHuman: i == 0, style: i == 0 ? nil : PokerStyle.allCases[i % 4], stack: stack)
        }
        return HoldemEngine(seats: seats, smallBlind: 5, bigBlind: 10, random: SeededRandomSource(seed: seed))
    }

    /// Ziehreihenfolge: Hole Cards reihum ab links vom Button (zwei Runden), dann Burn + Flop, Burn + Turn, Burn + River.
    private func deck(holeRound1: [String], holeRound2: [String], board: [String]) -> [Card] {
        let burn = cards("2c 2d 2h") // Burn-Karten spielen keine Rolle
        let b = board.flatMap { cards($0) }
        return holeRound1.flatMap { cards($0) } + holeRound2.flatMap { cards($0) }
            + [burn[0]] + Array(b[0..<3]) + [burn[1]] + [b[3]] + [burn[2]] + [b[4]]
    }

    private func allInEveryone(_ engine: HoldemEngine) throws {
        while engine.isHandInProgress, let idx = engine.currentIndex {
            let legal = engine.legalActions(forSeatAt: idx)!
            try engine.apply(legal.canRaise ? .allIn : .call, forSeatAt: idx)
        }
    }

    func testSplitPotOnBoardStraight() throws {
        // Heads-up, Button = Sitz 0. Ausgabe: Sitz 1, Sitz 0, Sitz 1, Sitz 0
        let engine = makeEngine(stacks: [100, 100])
        engine.buttonIndex = 1
        engine.testDeckForNextHand = deck(holeRound1: ["3h", "4h"], holeRound2: ["3s", "4s"],
                                          board: ["As", "Kd", "Qc", "Jh", "10s"])
        try engine.startHand()
        XCTAssertEqual(engine.seats[engine.buttonIndex].id, 0)
        try allInEveryone(engine)
        XCTAssertEqual(engine.lastShowdown.count, 2)
        XCTAssertEqual(engine.lastShowdown[0].hand, engine.lastShowdown[1].hand)
        XCTAssertEqual(engine.seats.map(\.stack), [100, 100], "Gleichstand → Pot wird geteilt")
    }

    func testKickerDecidesShowdown() throws {
        let engine = makeEngine(stacks: [100, 100])
        engine.buttonIndex = 1
        // Sitz 1: A♦ Q♣ · Sitz 0: A♣ K♦
        engine.testDeckForNextHand = deck(holeRound1: ["Ad", "Ac"], holeRound2: ["Qc", "Kd"],
                                          board: ["Ah", "7s", "4d", "2s", "9h"])
        try engine.startHand()
        try allInEveryone(engine)
        XCTAssertEqual(engine.seats.map(\.stack), [200, 0])
        XCTAssertEqual(engine.lastAwards.first?.handName, "Ein Paar")
    }

    func testSidePots() throws {
        // Button = Sitz 0, SB = Sitz 1, BB = Sitz 2. Ausgabe beginnt bei Sitz 1.
        let engine = makeEngine(stacks: [50, 200, 200])
        engine.buttonIndex = 2
        engine.testDeckForNextHand = deck(holeRound1: ["Kh", "Qh", "Ah"], holeRound2: ["Kd", "Qd", "Ad"],
                                          board: ["2s", "5d", "8h", "9s", "Jc"])
        try engine.startHand()
        try allInEveryone(engine)
        // Hauptpot 150 → Sitz 0 (Asse), Side-Pot 300 → Sitz 1 (Könige)
        XCTAssertEqual(engine.seats.map(\.stack), [150, 300, 0])
        XCTAssertEqual(Set(engine.lastAwards.map(\.potIndex)), [0, 1])
    }

    func testFoldWinsUncontested() throws {
        let engine = makeEngine(stacks: [100, 100])
        engine.buttonIndex = 1
        try engine.startHand()
        let first = engine.currentIndex!
        try engine.apply(.fold, forSeatAt: first)
        XCTAssertFalse(engine.isHandInProgress)
        XCTAssertTrue(engine.lastShowdown.isEmpty, "Ohne Showdown werden keine Karten gezeigt")
        XCTAssertEqual(engine.seats.reduce(0) { $0 + $1.stack }, 200)
        XCTAssertEqual(engine.seats[first].stack, 95, "Small Blind verloren")
    }

    func testBettingOrderAndMinRaise() throws {
        // 3 Spieler: Button 0, SB 1, BB 2 → preflop handelt zuerst Sitz 0, postflop Sitz 1.
        let engine = makeEngine(stacks: [1_000, 1_000, 1_000])
        engine.buttonIndex = 2
        try engine.startHand()
        XCTAssertEqual(engine.currentIndex, 0)
        let legal = engine.legalActions(forSeatAt: 0)!
        XCTAssertFalse(legal.canCheck)
        XCTAssertEqual(legal.callAmount, 10)
        XCTAssertEqual(legal.minRaiseTo, 20)
        XCTAssertThrowsError(try engine.apply(.raise(to: 15), forSeatAt: 0), "Raise unter Mindestbetrag")
        XCTAssertThrowsError(try engine.apply(.check, forSeatAt: 0), "Check trotz offenem Einsatz")
        XCTAssertThrowsError(try engine.apply(.call, forSeatAt: 1), "Nicht am Zug")
        try engine.apply(.raise(to: 30), forSeatAt: 0)
        XCTAssertEqual(engine.legalActions(forSeatAt: 1)?.minRaiseTo, 50, "Mindest-Reraise = letzte Erhöhung")
        try engine.apply(.call, forSeatAt: 1)
        try engine.apply(.call, forSeatAt: 2)
        XCTAssertEqual(engine.street, .flop)
        XCTAssertEqual(engine.community.count, 3)
        XCTAssertEqual(engine.pot, 90)
        XCTAssertEqual(engine.currentIndex, 1, "Postflop beginnt links vom Button")
        XCTAssertTrue(engine.legalActions(forSeatAt: 1)!.canCheck)
        try engine.apply(.check, forSeatAt: 1)
        try engine.apply(.raise(to: 40), forSeatAt: 2) // Bet
        XCTAssertEqual(engine.seats[2].lastAction?.kind, .bet)
        try engine.apply(.fold, forSeatAt: 0)
        try engine.apply(.call, forSeatAt: 1)
        XCTAssertEqual(engine.street, .turn)
        XCTAssertEqual(engine.pot, 170)
    }

    func testBigBlindOptionPreflop() throws {
        let engine = makeEngine(stacks: [1_000, 1_000, 1_000])
        engine.buttonIndex = 2
        try engine.startHand()
        try engine.apply(.call, forSeatAt: 0)
        try engine.apply(.call, forSeatAt: 1)
        XCTAssertEqual(engine.currentIndex, 2, "Big Blind darf noch handeln")
        XCTAssertTrue(engine.legalActions(forSeatAt: 2)!.canCheck)
        try engine.apply(.check, forSeatAt: 2)
        XCTAssertEqual(engine.street, .flop)
    }

    func testChipsAreConservedAndCardsUniqueOverManyHands() throws {
        let random = SeededRandomSource(seed: 99)
        let engine = makeEngine(stacks: [1_000, 400, 1_500, 250, 800, 2_000], seed: 5)
        for _ in 0..<2_000 {
            for i in engine.seats.indices where engine.seats[i].stack == 0 { try engine.setStack(500, forSeatAt: i) }
            let before = engine.seats.reduce(0) { $0 + $1.stack }
            try engine.startHand()
            let dealt = engine.seats.flatMap(\.holeCards)
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
            let all = dealt + engine.community
            XCTAssertEqual(Set(all.map(\.id)).count, all.count, "Karte doppelt ausgegeben")
            XCTAssertEqual(engine.seats.reduce(0) { $0 + $1.stack }, before, "Chips müssen erhalten bleiben")
            XCTAssertTrue(engine.seats.allSatisfy { $0.stack >= 0 })
            if !engine.lastShowdown.isEmpty { XCTAssertEqual(engine.community.count, 5) }
        }
    }

    func testAIProducesLegalActionsAndSeesNoHiddenCards() throws {
        let random = SeededRandomSource(seed: 3)
        let engine = makeEngine(stacks: [1_000, 1_000, 1_000, 1_000], seed: 8)
        for _ in 0..<40 {
            for i in engine.seats.indices where engine.seats[i].stack == 0 { try engine.setStack(1_000, forSeatAt: i) }
            try engine.startHand()
            while engine.isHandInProgress, let idx = engine.currentIndex {
                let ctx = PokerAIContext(engine: engine, seatIndex: idx)
                XCTAssertEqual(ctx.holeCards, engine.seats[idx].holeCards)
                XCTAssertEqual(ctx.community, engine.community)
                let action = PokerAI.decide(context: ctx, style: engine.seats[idx].style ?? .shark, random: random)
                XCTAssertNoThrow(try engine.apply(action, forSeatAt: idx), "\(action)")
            }
        }
    }

    func testAIDecisionsDoNotChangeTheDeal() throws {
        // Gleicher Karten-Seed, völlig unterschiedliche Spielweisen → identische Karten.
        func dealtCards(policy: (HoldemEngine, Int) -> PokerAction) throws -> [[Card]] {
            let engine = makeEngine(stacks: [5_000, 5_000, 5_000], seed: 21)
            var result: [[Card]] = []
            for _ in 0..<30 {
                try engine.startHand()
                while engine.isHandInProgress, let idx = engine.currentIndex {
                    try engine.apply(policy(engine, idx), forSeatAt: idx)
                }
                result.append(engine.seats.flatMap(\.holeCards))
                for i in engine.seats.indices { try engine.setStack(5_000, forSeatAt: i) }
            }
            return result
        }
        let passive = try dealtCards { engine, idx in engine.legalActions(forSeatAt: idx)!.canCheck ? .check : .call }
        let folding = try dealtCards { _, _ in .fold }
        XCTAssertEqual(passive, folding)
    }

    func testEquityEstimateIsSensible() {
        let random = SeededRandomSource(seed: 4)
        let aces = PokerAI.estimateEquity(hole: cards("As Ah"), community: [], opponents: 1, iterations: 2_000, random: random)
        let junk = PokerAI.estimateEquity(hole: cards("7c 2d"), community: [], opponents: 1, iterations: 2_000, random: random)
        XCTAssertEqual(aces, 0.85, accuracy: 0.04)
        XCTAssertEqual(junk, 0.35, accuracy: 0.05)
    }
}
