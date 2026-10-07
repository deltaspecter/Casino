import XCTest
@testable import CasinoCore

final class BlackjackTableTests: XCTestCase {
    private func c(_ rank: Rank, _ suit: Suit = .spades) -> Card { Card(rank, suit) }

    func testThreeSeatsPlayIndependentlyAgainstOneDealer() throws {
        let table = BlackjackTableEngine(random: SeededRandomSource(seed: 1))
        // Runde 1: S1, S2, S3, Dealer offen · Runde 2: S1, S2, S3, Dealer verdeckt · danach Aktionen
        table.testDeckForNextRound = [
            c(.ten), c(.five), c(.six), c(.nine, .hearts),
            c(.six, .hearts), c(.five, .hearts), c(.five, .clubs), c(.seven, .hearts),
            c(.nine, .clubs),          // S1 Hit → 25 Bust
            c(.ten, .diamonds),        // S3 Double → 21
            c(.two, .diamonds)         // Dealer 16 → 18
        ]
        try table.startRound(bets: [(seatID: 1, bet: 100), (seatID: 2, bet: 50), (seatID: 3, bet: 20)])
        XCTAssertEqual(table.currentSeatID, 1)
        XCTAssertThrowsError(try table.perform(.stand, seat: 2), "Nicht am Zug")
        XCTAssertTrue(table.availableActions(forSeat: 2).isEmpty)

        try table.perform(.hit, seat: 1)            // Spieler 1: Hit
        XCTAssertEqual(table.currentSeatID, 2)
        try table.perform(.stand, seat: 2)          // Spieler 2: Stand
        XCTAssertEqual(table.currentSeatID, 3)
        XCTAssertEqual(table.additionalStake(for: .double, seat: 3), 20)
        try table.perform(.double, seat: 3)         // Spieler 3: Double

        XCTAssertEqual(table.phase, .settled)
        XCTAssertEqual(HandValue.of(table.dealerCards).total, 18)
        XCTAssertEqual(table.seat(1)?.results.first?.outcome, .bust)
        XCTAssertEqual(table.seat(2)?.results.first?.outcome, .lose)   // 10 vs 18
        XCTAssertEqual(table.seat(3)?.results.first?.outcome, .win)    // 21 vs 18
        XCTAssertEqual(table.seat(3)?.results.first?.payout, 80)
    }

    func testSeatsAreIsolatedFromOtherSeatsActions() throws {
        // Gleicher Kartenstapel; nur die Aktion von Platz 1 unterscheidet sich.
        // Platz 2 erhält dieselben Startkarten – seine Hand gehört nur ihm.
        func run(seat1Action: BlackjackAction) throws -> [Card] {
            let table = BlackjackTableEngine(random: SeededRandomSource(seed: 3))
            table.testDeckForNextRound = [c(.ten), c(.nine), c(.six, .hearts), c(.seven, .hearts), c(.eight), c(.ten, .clubs),
                                          c(.two, .clubs), c(.three, .clubs), c(.four, .clubs)]
            try table.startRound(bets: [(seatID: 1, bet: 10), (seatID: 2, bet: 10)])
            try table.perform(seat1Action, seat: 1)
            return table.seat(2)!.hands[0].cards
        }
        XCTAssertEqual(try run(seat1Action: .stand), try run(seat1Action: .stand))
        XCTAssertEqual(try run(seat1Action: .hit).prefix(2), try run(seat1Action: .stand).prefix(2))
    }

    func testStandAllAndInvalidBets() throws {
        let table = BlackjackTableEngine(random: SeededRandomSource(seed: 4))
        XCTAssertThrowsError(try table.startRound(bets: []))
        XCTAssertThrowsError(try table.startRound(bets: [(seatID: 1, bet: 10), (seatID: 1, bet: 10)]))
        XCTAssertThrowsError(try table.startRound(bets: [(seatID: 1, bet: 1)]))
        table.testDeckForNextRound = [c(.ten), c(.nine), c(.six, .hearts), c(.seven, .hearts), c(.eight), c(.eight, .clubs)]
        try table.startRound(bets: [(seatID: 1, bet: 10), (seatID: 2, bet: 10)])
        table.standAll(seat: 1)
        XCTAssertEqual(table.currentSeatID, 2)
        table.standAll(seat: 2)
        XCTAssertEqual(table.phase, .settled)
    }

    func testManyMultiSeatRoundsNoDuplicateCards() throws {
        let random = SeededRandomSource(seed: 9)
        let table = BlackjackTableEngine(random: random)
        for _ in 0..<3_000 {
            try table.startRound(bets: (1...5).map { (seatID: $0, bet: 10) })
            while table.phase == .playerTurn, let seat = table.currentSeatID {
                let actions = Array(table.availableActions(forSeat: seat)).sorted { $0.rawValue < $1.rawValue }
                try table.perform(random.pick(actions)!, seat: seat)
            }
            let all = table.seats.flatMap { $0.hands.flatMap(\.cards) } + table.dealerCards
            XCTAssertEqual(Set(all.map(\.id)).count, all.count)
            XCTAssertEqual(table.seats.map { $0.results.count }, table.seats.map { $0.hands.count })
        }
    }

    func testBotUsesOnlyVisibleInformation() {
        let hand = BlackjackHand(id: 0, cards: [c(.ten), c(.six)], bet: 10)
        XCTAssertEqual(BlackjackBot.decide(hand: hand, dealerUpcard: c(.five), available: [.hit, .stand, .double]), .stand)
        XCTAssertEqual(BlackjackBot.decide(hand: hand, dealerUpcard: c(.ten), available: [.hit, .stand, .double]), .hit)
        let eleven = BlackjackHand(id: 0, cards: [c(.six), c(.five)], bet: 10)
        XCTAssertEqual(BlackjackBot.decide(hand: eleven, dealerUpcard: c(.nine), available: [.hit, .stand, .double]), .double)
        let aces = BlackjackHand(id: 0, cards: [c(.ace), c(.ace, .hearts)], bet: 10)
        XCTAssertEqual(BlackjackBot.decide(hand: aces, dealerUpcard: c(.nine), available: [.hit, .stand, .double, .split]), .split)
    }
}
