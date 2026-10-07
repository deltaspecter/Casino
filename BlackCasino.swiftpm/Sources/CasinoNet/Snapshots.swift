import Foundation

/// Sicht eines Spielers auf einen Online-Tisch. Wird vom Server **pro Empfänger** erzeugt:
/// verdeckte Karten anderer Spieler, die verdeckte Dealer-Karte und das Deck sind nie enthalten.
/// Der Client zeigt nur diesen Zustand an und berechnet selbst keine Ergebnisse.
public struct TableSnapshot: Codable, Equatable {
    public let tableID: String
    public let game: OnlineGame
    /// Steigt bei jeder Zustandsänderung. Alle Clients sehen bei gleicher Version denselben Tisch.
    public let version: Int
    public let isPrivate: Bool
    public let yourSeatID: Int?
    public let seats: [TableSeat]
    /// Bis wann der Spieler am Zug handeln muss (danach Standardaktion des Servers).
    public let turnDeadline: Date?
    public let blackjack: BlackjackTableSnapshot?
    public let poker: PokerTableSnapshot?

    public init(tableID: String, game: OnlineGame, version: Int, isPrivate: Bool, yourSeatID: Int?,
                seats: [TableSeat], turnDeadline: Date?, blackjack: BlackjackTableSnapshot?, poker: PokerTableSnapshot?) {
        self.tableID = tableID
        self.game = game
        self.version = version
        self.isPrivate = isPrivate
        self.yourSeatID = yourSeatID
        self.seats = seats
        self.turnDeadline = turnDeadline
        self.blackjack = blackjack
        self.poker = poker
    }

    public func seat(_ id: Int) -> TableSeat? { seats.first { $0.seatID == id } }
}

public struct TableSeat: Codable, Equatable, Identifiable {
    public let seatID: Int
    public let player: PlayerInfo
    public let isBot: Bool
    public let botStyle: String?
    public let isConnected: Bool
    public var id: Int { seatID }

    public init(seatID: Int, player: PlayerInfo, isBot: Bool, botStyle: String?, isConnected: Bool) {
        self.seatID = seatID
        self.player = player
        self.isBot = isBot
        self.botStyle = botStyle
        self.isConnected = isConnected
    }
}

// MARK: - Blackjack

public struct BlackjackHandSnapshot: Codable, Equatable, Identifiable {
    public let id: Int
    public let cards: [Card]
    public let bet: Int
    public let isDoubled: Bool
    public let result: HandResult?

    public init(id: Int, cards: [Card], bet: Int, isDoubled: Bool, result: HandResult?) {
        self.id = id
        self.cards = cards
        self.bet = bet
        self.isDoubled = isDoubled
        self.result = result
    }

    public var value: HandValue { HandValue.of(cards) }
}

public struct BlackjackSeatSnapshot: Codable, Equatable, Identifiable {
    public let seatID: Int
    /// Einsatz für die nächste Runde (Setzphase).
    public let pendingBet: Int?
    public let hands: [BlackjackHandSnapshot]
    public var id: Int { seatID }

    public init(seatID: Int, pendingBet: Int?, hands: [BlackjackHandSnapshot]) {
        self.seatID = seatID
        self.pendingBet = pendingBet
        self.hands = hands
    }
}

public struct BlackjackTableSnapshot: Codable, Equatable {
    public let phase: BlackjackPhase
    public let bettingOpen: Bool
    /// Dealer-Karten; `nil` steht für die noch verdeckte Karte.
    public let dealerCards: [Card?]
    public let seats: [BlackjackSeatSnapshot]
    public let currentSeatID: Int?
    public let currentHandID: Int?
    public let minBet: Int
    public let maxBet: Int
    /// Nur für den Empfänger, wenn er am Zug ist.
    public let yourActions: [BlackjackAction]
    public let yourAdditionalStake: Int

    public init(phase: BlackjackPhase, bettingOpen: Bool, dealerCards: [Card?], seats: [BlackjackSeatSnapshot],
                currentSeatID: Int?, currentHandID: Int?, minBet: Int, maxBet: Int,
                yourActions: [BlackjackAction], yourAdditionalStake: Int) {
        self.phase = phase
        self.bettingOpen = bettingOpen
        self.dealerCards = dealerCards
        self.seats = seats
        self.currentSeatID = currentSeatID
        self.currentHandID = currentHandID
        self.minBet = minBet
        self.maxBet = maxBet
        self.yourActions = yourActions
        self.yourAdditionalStake = yourAdditionalStake
    }

    /// Wert der offenen Dealer-Karten.
    public var dealerVisibleValue: HandValue? {
        let visible = dealerCards.compactMap { $0 }
        return visible.isEmpty ? nil : HandValue.of(visible)
    }
}

// MARK: - Poker

public struct PokerPlayerSnapshot: Codable, Equatable, Identifiable {
    public let seatID: Int
    public let stack: Int
    public let streetBet: Int
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isSittingOut: Bool
    public let hasCards: Bool
    /// Nur eigene Karten oder beim Showdown aufgedeckte Karten.
    public let holeCards: [Card]?
    public let lastAction: PokerActionRecord?
    public var id: Int { seatID }

    public init(seatID: Int, stack: Int, streetBet: Int, hasFolded: Bool, isAllIn: Bool, isSittingOut: Bool,
                hasCards: Bool, holeCards: [Card]?, lastAction: PokerActionRecord?) {
        self.seatID = seatID
        self.stack = stack
        self.streetBet = streetBet
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
        self.isSittingOut = isSittingOut
        self.hasCards = hasCards
        self.holeCards = holeCards
        self.lastAction = lastAction
    }
}

public struct ShowdownSnapshot: Codable, Equatable {
    public let seatID: Int
    public let handName: String

    public init(seatID: Int, handName: String) {
        self.seatID = seatID
        self.handName = handName
    }
}

public struct PokerTableSnapshot: Codable, Equatable {
    public let handNumber: Int
    public let isHandInProgress: Bool
    public let street: PokerStreet
    public let community: [Card]
    public let pot: Int
    public let currentBet: Int
    public let smallBlind: Int
    public let bigBlind: Int
    public let buttonSeatID: Int?
    public let currentSeatID: Int?
    public let players: [PokerPlayerSnapshot]
    public let showdown: [ShowdownSnapshot]
    public let awards: [PotAward]
    /// Nur für den Empfänger, wenn er am Zug ist.
    public let yourLegalActions: PokerLegalActions?

    public init(handNumber: Int, isHandInProgress: Bool, street: PokerStreet, community: [Card], pot: Int,
                currentBet: Int, smallBlind: Int, bigBlind: Int, buttonSeatID: Int?, currentSeatID: Int?,
                players: [PokerPlayerSnapshot], showdown: [ShowdownSnapshot], awards: [PotAward],
                yourLegalActions: PokerLegalActions?) {
        self.handNumber = handNumber
        self.isHandInProgress = isHandInProgress
        self.street = street
        self.community = community
        self.pot = pot
        self.currentBet = currentBet
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.buttonSeatID = buttonSeatID
        self.currentSeatID = currentSeatID
        self.players = players
        self.showdown = showdown
        self.awards = awards
        self.yourLegalActions = yourLegalActions
    }

    public func player(_ seatID: Int) -> PokerPlayerSnapshot? { players.first { $0.seatID == seatID } }
}
