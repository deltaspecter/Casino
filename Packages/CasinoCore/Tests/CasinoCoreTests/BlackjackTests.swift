import XCTest
@testable import CasinoCore

final class BlackjackTests: XCTestCase {
    private func c(_ rank: Rank, _ suit: Suit = .spades) -> Card { Card(rank, suit) }

    func testHandValues() {
        XCTAssertEqual(HandValue.of([c(.ace), c(.king)]), HandValue(total: 21, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.ace), c(.nine)]), HandValue(total: 21, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.ace), c(.ace)]), HandValue(total: 13, isSoft: true))
        XCTAssertEqual(HandValue.of([c(.ace), c(.six), c(.king)]), HandValue(total: 17, isSoft: false))
        XCTAssertEqual(HandValue.of([c(.king), c(.queen), c(.two)]), HandValue(total: 22, isSoft: false))
        XCTAssertEqual(HandValue.of([c(.ace), c(.six)]).display, "7/17")
    }

    func testSplitTwentyOneIsNotBlackjack() {
        let hand = BlackjackHand(id: 0, cards: [c(.ace), c(.king)], bet: 10, isFromSplit: true)
        XCTAssertFalse(hand.isBlackjack)
        XCTAssertTrue(BlackjackHand(id: 0, cards: [c(.ace), c(.king)], bet: 10).isBlackjack)
    }

    func testRejectsInvalidBets() {
        let engine = BlackjackEngine(random: SeededRandomSource(seed: 1))
        XCTAssertThrowsError(try engine.startRound(bet: 1))
        XCTAssertThrowsError(try engine.startRound(bet: 1_000_000))
    }

    /// Spielt viele Runden mit zufälligen legalen Aktionen und prüft Invarianten.
    func testManyRandomRoundsKeepInvariants() throws {
        let random = SeededRandomSource(seed: 42)
        let engine = BlackjackEngine(random: random)
        var totalStake = 0
        var totalPayout = 0

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

            // Dealer hält sich an S17, sofern die Runde nicht sofort (Blackjack) oder
            // mangels lebender Spielerhände endete
            let dealer = HandValue.of(engine.dealerCards)
            let endedImmediately = (engine.dealerCards.count == 2 && dealer.total == 21)
                || (engine.hands.count == 1 && engine.hands[0].isBlackjack)
            if engine.hands.contains(where: { !$0.isBust }) && !endedImmediately {
                XCTAssertGreaterThanOrEqual(dealer.total, 17)
                let withoutLast = HandValue.of(Array(engine.dealerCards.dropLast()))
                if engine.dealerCards.count > 2 { XCTAssertLessThan(withoutLast.total, 17) }
            }

            for (hand, result) in zip(engine.hands, engine.results) {
                XCTAssertEqual(hand.bet, result.stake)
                switch result.outcome {
                case .blackjack: XCTAssertEqual(result.payout, hand.bet * 5 / 2)
                case .win: XCTAssertEqual(result.payout, hand.bet * 2)
                case .push: XCTAssertEqual(result.payout, hand.bet)
                case .lose, .bust: XCTAssertEqual(result.payout, 0)
                }
                totalStake += result.stake
                totalPayout += result.payout
            }
        }
        // Zufällige Spielweise verliert langfristig deutlich – aber nicht alles.
        let rtp = Double(totalPayout) / Double(totalStake)
        XCTAssertGreaterThan(rtp, 0.5)
        XCTAssertLessThan(rtp, 1.0)
    }

    func testBasicStrategyReturnIsRealistic() throws {
        // Einfache Strategie: stehen ab 17, sonst ziehen. Erwartete Quote ~92–97 %.
        let random = SeededRandomSource(seed: 7)
        let engine = BlackjackEngine(random: random)
        var stake = 0, payout = 0
        for _ in 0..<50_000 {
            try engine.startRound(bet: 10)
            while engine.phase == .playerTurn {
                let total = engine.activeHand!.value.total
                try engine.perform(total >= 17 ? .stand : .hit)
            }
            stake += engine.results.reduce(0) { $0 + $1.stake }
            payout += engine.results.reduce(0) { $0 + $1.payout }
        }
        let rtp = Double(payout) / Double(stake)
        XCTAssertGreaterThan(rtp, 0.90)
        XCTAssertLessThan(rtp, 1.0)
    }

    func testIllegalActionThrows() throws {
        let random = SeededRandomSource(seed: 11)
        let engine = BlackjackEngine(random: random)
        for _ in 0..<200 {
            try engine.startRound(bet: 10)
            if engine.phase == .playerTurn && !engine.availableActions().contains(.split) {
                XCTAssertThrowsError(try engine.perform(.split))
                return
            }
        }
        XCTFail("Keine passende Runde gefunden")
    }
}
