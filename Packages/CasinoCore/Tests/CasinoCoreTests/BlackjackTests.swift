import XCTest
@testable import CasinoCore

final class BlackjackTests: XCTestCase {
    private func c(_ rank: Rank, _ suit: Suit = .spades) -> Card { Card(rank, suit) }

    /// Spielt eine Runde mit fest vorgegebener Ziehreihenfolge
    /// (Spieler, Dealer offen, Spieler, Dealer verdeckt, danach weitere Karten).
    private func scenario(_ deck: [Card], bet: Int = 100, actions: [BlackjackAction] = [],
                          file: StaticString = #filePath, line: UInt = #line) throws -> BlackjackEngine {
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 1))
        engine.testDeckForNextRound = deck
        try engine.startRound(bet: bet)
        for action in actions {
            XCTAssertEqual(engine.phase, .playerTurn, "Aktion \(action) ohne Spielerzug", file: file, line: line)
            try engine.perform(action)
        }
        XCTAssertEqual(engine.phase, .settled, file: file, line: line)
        return engine
    }

    // MARK: - Handbewertung

    func testHandValues() {
        XCTAssertEqual(HandValue.of([c(.ace), c(.king)]), HandValue(total: 21, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.ace), c(.nine)]), HandValue(total: 21, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.ace), c(.ace)]), HandValue(total: 13, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.six), c(.king)]), HandValue(total: 17, isSoft: false))
        XCTAssertEqual(HandValue.of([c(.king), c(.queen), c(.two)]), HandValue(total: 22, isSoft: false))
        XCTAssertEqual(HandValue.of([c(.ace), c(.six)]).display, "7/17")
        XCTAssertEqual(HandValue.of([c(.ace), c(.ace), c(.ace), c(.ace), c(.seven)]), HandValue(total: 21, isSoft: true))
    }

    func testSplitTwentyOneIsNotBlackjack() {
        XCTAssertFalse(BlackjackHand(id: 0, cards: [c(.ace), c(.king)], bet: 10, isFromSplit: true).isBlackjack)
        XCTAssertTrue(BlackjackHand(id: 0, cards: [c(.ace), c(.king)], bet: 10).isBlackjack)
        XCTAssertFalse(BlackjackHand(id: 0, cards: [c(.seven), c(.seven), c(.seven)], bet: 10).isBlackjack)
    }

    func testRejectsInvalidBetsAndActions() throws {
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 1))
        XCTAssertThrowsError(try engine.startRound(bet: 1))
        XCTAssertThrowsError(try engine.startRound(bet: 1_000_000))
        XCTAssertThrowsError(try engine.perform(.hit)) // keine Runde aktiv
        engine.testDeckForNextRound = [c(.ten), c(.seven), c(.eight), c(.ten)]
        try engine.startRound(bet: 10)
        XCTAssertThrowsError(try engine.perform(.split)) // kein Paar
        XCTAssertThrowsError(try engine.startRound(bet: 10)) // Runde läuft noch
    }

    // MARK: - Regelszenarien

    func testPlayerBlackjackPaysThreeToTwo() throws {
        let e = try scenario([c(.ace), c(.nine, .hearts), c(.king), c(.seven, .clubs)])
        XCTAssertEqual(e.results.first?.outcome, .blackjack)
        XCTAssertEqual(e.results.first?.payout, 250)
        XCTAssertEqual(e.dealerCards.count, 2, "Dealer zieht nach Spieler-Blackjack nicht")
    }

    func testDealerBlackjackBeatsPlayer() throws {
        let e = try scenario([c(.nine), c(.ace, .hearts), c(.nine, .clubs), c(.king, .hearts)])
        XCTAssertEqual(e.results.first?.outcome, .lose)
        XCTAssertEqual(e.results.first?.payout, 0)
        XCTAssertTrue(e.isHoleCardRevealed)
    }

    func testBothBlackjackIsPush() throws {
        let e = try scenario([c(.ace), c(.ace, .hearts), c(.king), c(.queen, .hearts)])
        XCTAssertEqual(e.results.first?.outcome, .push)
        XCTAssertEqual(e.results.first?.payout, 100)
    }

    func testPlayerBust() throws {
        let e = try scenario([c(.ten), c(.seven, .hearts), c(.six), c(.ten, .hearts), c(.nine)], actions: [.hit])
        XCTAssertEqual(e.results.first?.outcome, .bust)
        XCTAssertEqual(e.results.first?.payout, 0)
        XCTAssertEqual(e.dealerCards.count, 2, "Bei überkaufter Spielerhand zieht der Dealer nicht")
    }

    func testPush() throws {
        let e = try scenario([c(.ten), c(.ten, .hearts), c(.eight), c(.eight, .hearts)], actions: [.stand])
        XCTAssertEqual(e.results.first?.outcome, .push)
        XCTAssertEqual(e.results.first?.payout, 100)
    }

    func testDealerBust() throws {
        let e = try scenario([c(.ten), c(.ten, .hearts), c(.eight), c(.six, .hearts), c(.king, .clubs)], actions: [.stand])
        XCTAssertEqual(HandValue.of(e.dealerCards).total, 26)
        XCTAssertEqual(e.results.first?.outcome, .win)
        XCTAssertEqual(e.results.first?.payout, 200)
    }

    func testDealerStandsOnSoft17() throws {
        let e = try scenario([c(.ten), c(.ace, .hearts), c(.nine), c(.six, .hearts), c(.five, .clubs)], actions: [.stand])
        XCTAssertEqual(e.dealerCards.count, 2)
        XCTAssertEqual(HandValue.of(e.dealerCards), HandValue(total: 17, isSoft: true))
        XCTAssertEqual(e.results.first?.outcome, .win)
    }

    func testDealerHitsSixteenAndSoftHandsResolveCorrectly() throws {
        // Spieler: A+5 (soft 16) → Hit 4 → soft 20. Dealer: 10+6 → zieht 5 → 21.
        let e = try scenario([c(.ace), c(.ten, .hearts), c(.five), c(.six, .hearts), c(.four), c(.five, .clubs)],
                             actions: [.hit, .stand])
        XCTAssertEqual(e.hands[0].value, HandValue(total: 20, isSoft: true))
        XCTAssertEqual(HandValue.of(e.dealerCards).total, 21)
        XCTAssertEqual(e.results.first?.outcome, .lose)
    }

    func testDoubleDown() throws {
        let e = try scenario([c(.five), c(.nine, .hearts), c(.six), c(.seven, .hearts), c(.king), c(.two, .clubs)],
                             actions: [.double])
        XCTAssertEqual(e.hands[0].cards.count, 3, "Nach Double genau eine Karte")
        XCTAssertEqual(e.hands[0].bet, 200)
        XCTAssertEqual(e.results.first?.outcome, .win)
        XCTAssertEqual(e.results.first?.payout, 400)
    }

    func testSplit() throws {
        let e = try scenario([c(.eight), c(.ten, .hearts), c(.eight, .clubs), c(.seven, .hearts), c(.three), c(.ten, .clubs)],
                             actions: [.split, .stand, .stand])
        XCTAssertEqual(e.hands.count, 2)
        XCTAssertEqual(e.hands.map(\.value.total), [11, 18])
        XCTAssertEqual(e.results.map(\.outcome), [.lose, .win])
        XCTAssertEqual(e.totalStake, 200)
    }

    func testSplitAcesGetOneCardAndTwentyOneIsNotBlackjack() throws {
        let e = try scenario([c(.ace), c(.nine, .hearts), c(.ace, .clubs), c(.seven, .hearts),
                              c(.king), c(.five), c(.five, .hearts)],
                             actions: [.split])
        XCTAssertEqual(e.hands.map { $0.cards.count }, [2, 2])
        XCTAssertEqual(HandValue.of(e.dealerCards).total, 21)
        XCTAssertEqual(e.results.map(\.outcome), [.push, .lose], "21 aus geteilten Assen ist kein Blackjack")
    }

    func testDoubleAfterSplit() throws {
        let e = try scenario([c(.nine), c(.six, .hearts), c(.nine, .clubs), c(.ten, .hearts),
                              c(.two), c(.ace), c(.eight), c(.king, .clubs)],
                             actions: [.split, .double, .stand])
        // Hand 1: 9+2 → Double → 8 = 19 · Hand 2: 9+A = 20 · Dealer 16 → K = Bust
        XCTAssertEqual(e.hands[0].bet, 200)
        XCTAssertEqual(e.results.map(\.outcome), [.win, .win])
        XCTAssertEqual(e.results.reduce(0) { $0 + $1.payout }, 600)
    }

    // MARK: - Zufallsrunden

    func testNoDuplicateCardsWithinARound() throws {
        let random = SeededRandomSource(seed: 5)
        let engine = BlackjackEngine(random: random)
        for _ in 0..<5_000 {
            try engine.startRound(bet: 10)
            while engine.phase == .playerTurn {
                let actions = Array(engine.availableActions()).sorted { $0.rawValue < $1.rawValue }
                try engine.perform(random.pick(actions)!)
            }
            let all = engine.hands.flatMap(\.cards) + engine.dealerCards
            XCTAssertEqual(Set(all.map(\.id)).count, all.count, "Karte doppelt in einer Runde")
            XCTAssertEqual(engine.shoe.remaining, 52 - all.count)
        }
    }

    func testManyRandomRoundsKeepInvariants() throws {
        let random = SeededRandomSource(seed: 42)
        let engine = BlackjackEngine(random: random)
        var totalStake = 0, totalPayout = 0

        for _ in 0..<20_000 {
            try engine.startRound(bet: 100)
            while engine.phase == .playerTurn {
                let actions = Array(engine.availableActions()).sorted { $0.rawValue < $1.rawValue }
                XCTAssertFalse(actions.isEmpty)
                try engine.perform(random.pick(actions)!)
            }
            XCTAssertEqual(engine.phase, .settled)
            XCTAssertTrue(engine.isHoleCardRevealed)
            XCTAssertEqual(engine.results.count, engine.hands.count)
            XCTAssertLessThanOrEqual(engine.hands.count, engine.rules.maxHands)

            let dealer = HandValue.of(engine.dealerCards)
            let endedImmediately = (engine.dealerCards.count == 2 && dealer.total == 21)
                || (engine.hands.count == 1 && engine.hands[0].isBlackjack)
            if engine.hands.contains(where: { !$0.isBust }) && !endedImmediately {
                XCTAssertGreaterThanOrEqual(dealer.total, 17)
                if engine.dealerCards.count > 2 {
                    XCTAssertLessThan(HandValue.of(Array(engine.dealerCards.dropLast())).total, 17)
                }
            }
            for (hand, result) in zip(engine.hands, engine.results) {
                XCTAssertEqual(hand.bet, result.stake)
                switch result.outcome {
                case .blackjack: XCTAssertEqual(result.payout, hand.bet * 5 / 2)
                case .win: XCTAssertEqual(result.payout, hand.bet * 2)
                case .push: XCTAssertEqual(result.payout, hand.bet)
                case .lose, .bust: XCTAssertEqual(result.payout, 0)
                }
                XCTAssertGreaterThanOrEqual(result.payout, 0)
                totalStake += result.stake
                totalPayout += result.payout
            }
        }
        let rtp = Double(totalPayout) / Double(totalStake)
        XCTAssertGreaterThan(rtp, 0.5)
        XCTAssertLessThan(rtp, 1.0)
    }

    func testSimpleStrategyReturnIsRealistic() throws {
        // Stehen ab 17, sonst ziehen: langfristig ca. 92–97 %.
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 7))
        var stake = 0, payout = 0
        for _ in 0..<50_000 {
            try engine.startRound(bet: 10)
            while engine.phase == .playerTurn {
                try engine.perform(engine.activeHand!.value.total >= 17 ? .stand : .hit)
            }
            stake += engine.results.reduce(0) { $0 + $1.stake }
            payout += engine.results.reduce(0) { $0 + $1.payout }
        }
        let rtp = Double(payout) / Double(stake)
        XCTAssertGreaterThan(rtp, 0.90)
        XCTAssertLessThan(rtp, 1.0)
    }

    func testConsecutiveRoundsAreFreshlyShuffled() throws {
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 9))
        var shuffles = engine.shoe.shuffleCount
        for _ in 0..<50 {
            try engine.startRound(bet: 10)
            XCTAssertEqual(engine.shoe.shuffleCount, shuffles + 1, "Jede Runde beginnt mit neu gemischtem Deck")
            shuffles = engine.shoe.shuffleCount
            while engine.phase == .playerTurn { try engine.perform(.stand) }
        }
    }
}
