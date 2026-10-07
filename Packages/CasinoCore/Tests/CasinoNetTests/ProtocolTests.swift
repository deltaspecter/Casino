import XCTest
import CasinoCore
@testable import CasinoNet

final class ProtocolTests: XCTestCase {
    func testClientMessagesRoundTrip() throws {
        let messages: [ClientMessage] = [
            .hello(HelloRequest(token: nil, displayName: "Kim")),
            .createRoom(game: .poker), .joinRoom(code: "A7K9P2"), .startRoom, .leaveRoom,
            .findMatch(game: .blackjack), .matchWithBots, .keepWaiting, .cancelMatch,
            .tableAction(TableActionRequest(stateVersion: 3, action: .poker(action: .raise(to: 40)))),
            .tableAction(TableActionRequest(stateVersion: 4, action: .blackjack(action: .double))),
            .tableAction(TableActionRequest(stateVersion: 5, action: .placeBet(amount: 100))),
            .addFriend(friendCode: "BC1234"), .inviteFriend(playerID: "p1"), .ping
        ]
        for m in messages {
            let text = try WireCodec.encode(m)
            XCTAssertEqual(try WireCodec.decode(ClientMessage.self, from: text), m)
        }
    }

    func testServerSnapshotRoundTrip() throws {
        let player = PlayerInfo(id: "p1", displayName: "Kim", friendCode: "ABC123")
        let snap = TableSnapshot(
            tableID: "t1", game: .blackjack, version: 7, isPrivate: true, yourSeatID: 0,
            seats: [TableSeat(seatID: 0, player: player, isBot: false, botStyle: nil, isConnected: true)],
            turnDeadline: Date(timeIntervalSince1970: 1_000),
            blackjack: BlackjackTableSnapshot(phase: .playerTurn, bettingOpen: false,
                                              dealerCards: [Card(.ace, .spades), nil],
                                              seats: [BlackjackSeatSnapshot(seatID: 0, pendingBet: nil, hands: [
                                                BlackjackHandSnapshot(id: 0, cards: [Card(.ten, .hearts), Card(.six, .clubs)], bet: 50, isDoubled: false, result: nil)])],
                                              currentSeatID: 0, currentHandID: 0, minBet: 10, maxBet: 1_000,
                                              yourActions: [.hit, .stand], yourAdditionalStake: 50),
            poker: nil)
        let text = try WireCodec.encode(ServerMessage.table(snap))
        XCTAssertEqual(try WireCodec.decode(ServerMessage.self, from: text), .table(snap))
        XCTAssertEqual(snap.blackjack?.dealerVisibleValue?.total, 11)
    }

    func testRejectsOversizedMessages() {
        let huge = String(repeating: "x", count: WireCodec.maxMessageBytes + 1)
        XCTAssertThrowsError(try WireCodec.decode(ClientMessage.self, from: huge))
        XCTAssertThrowsError(try WireCodec.decode(ClientMessage.self, from: "{\"kaputt\":1}"))
    }

    func testRoomCodes() {
        XCTAssertEqual(RoomCode.normalize(" a7k-9p2 "), "A7K9P2")
        XCTAssertNil(RoomCode.normalize("A7K9P"))
        XCTAssertNil(RoomCode.normalize("A7K9P0"), "0 ist nicht im Alphabet")
        for _ in 0..<200 {
            let code = RoomCode.generate()
            XCTAssertEqual(RoomCode.normalize(code), code)
        }
    }

    func testActionGatePreventsDoubleActions() {
        var gate = ActionGate()
        let first = gate.begin()
        XCTAssertNotNil(first)
        XCTAssertNil(gate.begin(), "Zweiter Tap wird verworfen")
        gate.resolve(UUID())
        XCTAssertTrue(gate.isBusy, "Fremde Antwort löst nichts")
        gate.resolve(first!)
        XCTAssertNotNil(gate.begin())
    }

    func testReconnectPolicyIsBounded() {
        let policy = ReconnectPolicy()
        XCTAssertNotNil(policy.delay(forAttempt: 0))
        XCTAssertNil(policy.delay(forAttempt: policy.delays.count))
        XCTAssertLessThan(policy.totalDuration, 90)
    }
}
