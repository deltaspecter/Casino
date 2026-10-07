import Foundation

/// Tischregeln von BlackCasino (im Spiel unter „Rules“ einsehbar):
/// * 1 Standard-Deck (52 Karten), **vor jeder Runde vollständig neu gemischt** –
///   dadurch ist jede Runde unabhängig von allen vorherigen.
/// * Dealer erhält eine offene und eine verdeckte Karte und prüft bei Ass oder 10er auf Blackjack (Peek).
/// * Dealer zieht bis 16 und **steht auf allen 17** (auch Soft 17, „S17“).
/// * Blackjack zahlt 3:2, normaler Gewinn 1:1, Push gibt den Einsatz zurück.
/// * Double Down auf beliebige erste zwei Karten (auch nach Split), genau eine weitere Karte.
/// * Split bei zwei Karten gleichen Werts, bis zu 4 Hände; geteilte Asse erhalten je eine Karte
///   und dürfen nicht erneut geteilt werden. 21 nach Split zählt nicht als Blackjack.
/// * Keine Insurance, kein Surrender.
public struct BlackjackRules: Equatable {
    public var deckCount = 1
    public var dealerHitsSoft17 = false
    public var doubleAfterSplit = true
    public var maxHands = 4
    public var resplitAces = false
    public var minBet = 10
    public var maxBet = 5_000

    public init() {}

    public init(minBet: Int, maxBet: Int) {
        self.minBet = minBet
        self.maxBet = maxBet
    }
}

public enum BlackjackPhase: String, Equatable, Codable {
    case betting, playerTurn, dealerTurn, settled
}

public enum BlackjackAction: String, CaseIterable, Equatable, Codable {
    case hit, stand, double, split
}

public enum BlackjackEvent: Equatable {
    case shuffled
    case dealtToPlayer(handID: Int, card: Card)
    case dealtToDealer(card: Card, faceDown: Bool)
    case holeCardRevealed(Card)
    case split(originalHandID: Int, newHandID: Int, movedCard: Card)
    case doubled(handID: Int)
    case activeHandChanged(handID: Int?)
    case settled([HandResult])
}

public enum BlackjackError: Error, Equatable {
    case invalidPhase
    case invalidBet
    case notYourTurn
    case illegalAction(BlackjackAction)
}

/// Einzelspieler-Blackjack (Offline). Eine dünne Hülle um `BlackjackTableEngine` mit genau
/// einem Platz – damit gelten offline und online exakt dieselben Regeln aus derselben Implementierung.
public final class BlackjackEngine {
    private static let seatID = 0
    private let table: BlackjackTableEngine

    public init(rules: BlackjackRules = BlackjackRules(), random: RandomSource) {
        table = BlackjackTableEngine(rules: rules, random: random)
    }

    // MARK: - Abfragen

    public var rules: BlackjackRules { table.rules }
    public var shoe: Shoe { table.shoe }
    public var phase: BlackjackPhase { table.phase }
    public var dealerCards: [Card] { table.dealerCards }
    public var isHoleCardRevealed: Bool { table.isHoleCardRevealed }
    public var dealerVisibleValue: HandValue { table.dealerVisibleValue }
    public var hands: [BlackjackHand] { table.seat(Self.seatID)?.hands ?? [] }
    public var results: [HandResult] { table.seat(Self.seatID)?.results ?? [] }
    public var activeHandIndex: Int? { table.turn?.hand }
    public var activeHand: BlackjackHand? { table.currentHand }
    public var totalStake: Int { hands.reduce(0) { $0 + $1.bet } }

    /// Nur für Unit-Tests (über `@testable import`).
    var testDeckForNextRound: [Card]? {
        get { table.testDeckForNextRound }
        set { table.testDeckForNextRound = newValue }
    }

    public func availableActions() -> Set<BlackjackAction> { table.availableActions(forSeat: Self.seatID) }

    public func additionalStake(for action: BlackjackAction) -> Int {
        table.additionalStake(for: action, seat: Self.seatID)
    }

    // MARK: - Ablauf

    @discardableResult
    public func startRound(bet: Int) throws -> [BlackjackEvent] {
        try table.startRound(bets: [(seatID: Self.seatID, bet: bet)]).map(Self.translate)
    }

    @discardableResult
    public func perform(_ action: BlackjackAction) throws -> [BlackjackEvent] {
        guard phase == .playerTurn else { throw BlackjackError.invalidPhase }
        return try table.perform(action, seat: Self.seatID).map(Self.translate)
    }

    private static func translate(_ event: BlackjackTableEvent) -> BlackjackEvent {
        switch event {
        case .shuffled: return .shuffled
        case let .dealtToPlayer(_, handID, card): return .dealtToPlayer(handID: handID, card: card)
        case let .dealtToDealer(card, faceDown): return .dealtToDealer(card: card, faceDown: faceDown)
        case let .holeCardRevealed(card): return .holeCardRevealed(card)
        case let .split(_, original, new, moved): return .split(originalHandID: original, newHandID: new, movedCard: moved)
        case let .doubled(_, handID): return .doubled(handID: handID)
        case let .turnChanged(_, handID): return .activeHandChanged(handID: handID)
        case let .settled(seatResults): return .settled(seatResults.first?.results ?? [])
        }
    }
}
