import Foundation
import CasinoCore

/// Version des Netzwerkprotokolls. Bei inkompatiblen Änderungen erhöhen.
public let blackCasinoProtocolVersion = 1

// MARK: - Grundtypen

public enum OnlineGame: String, Codable, CaseIterable, Identifiable {
    case blackjack, poker

    public var id: String { rawValue }
    public var title: String { self == .blackjack ? "Blackjack" : "Poker" }

    /// Spielerlimits für Räume und Tische.
    public var minPlayers: Int { 2 }
    public var maxPlayers: Int { self == .blackjack ? 5 : 6 }
}

public struct PlayerInfo: Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    /// Kurzer, teilbarer Code zum Hinzufügen als Freund.
    public let friendCode: String

    public init(id: String, displayName: String, friendCode: String) {
        self.id = id
        self.displayName = displayName
        self.friendCode = friendCode
    }
}

public enum Presence: String, Codable, Equatable {
    case online, offline, inGame
}

public struct FriendInfo: Codable, Equatable, Identifiable {
    public let player: PlayerInfo
    public let presence: Presence
    public var id: String { player.id }

    public init(player: PlayerInfo, presence: Presence) {
        self.player = player
        self.presence = presence
    }
}

/// Konto für das Online-Spiel. Online-Chips werden ausschließlich vom Server verwaltet
/// und sind – wie alle Chips – rein virtuell ohne Geldwert.
public struct AccountInfo: Codable, Equatable {
    public let player: PlayerInfo
    public let onlineChips: Int
    /// Nur bei der Erstregistrierung gesetzt. Der Client speichert ihn sicher (Keychain).
    public let token: String?

    public init(player: PlayerInfo, onlineChips: Int, token: String?) {
        self.player = player
        self.onlineChips = onlineChips
        self.token = token
    }
}

// MARK: - Räume & Matchmaking

public enum RoomStatus: String, Codable, Equatable {
    case waiting, inGame
}

public struct RoomInfo: Codable, Equatable {
    public let code: String
    public let game: OnlineGame
    public let hostID: String
    public let members: [PlayerInfo]
    public let status: RoomStatus

    public init(code: String, game: OnlineGame, hostID: String, members: [PlayerInfo], status: RoomStatus) {
        self.code = code
        self.game = game
        self.hostID = hostID
        self.members = members
        self.status = status
    }

    public var maxPlayers: Int { game.maxPlayers }
    public var canStart: Bool { status == .waiting && members.count >= game.minPlayers }
}

public struct Invitation: Codable, Equatable, Identifiable {
    public let roomCode: String
    public let game: OnlineGame
    public let from: PlayerInfo
    public var id: String { roomCode + from.id }

    public init(roomCode: String, game: OnlineGame, from: PlayerInfo) {
        self.roomCode = roomCode
        self.game = game
        self.from = from
    }
}

public enum MatchmakingStatus: Codable, Equatable {
    case searching(game: OnlineGame, since: Date)
    /// Nach kurzer Wartezeit kein passender Spieler: Bots anbieten.
    case noMatchFound(game: OnlineGame)
    case matched(tableID: String)
    case idle
}

// MARK: - Tischaktionen

public enum TableAction: Codable, Equatable {
    case placeBet(amount: Int)
    case blackjack(action: BlackjackAction)
    case poker(action: PokerAction)
    case rebuy
}

public struct TableActionRequest: Codable, Equatable {
    /// Eindeutige ID: Der Server verarbeitet jede ID höchstens einmal (Schutz vor Doppel-Taps).
    public let actionID: UUID
    /// Version des Spielstands, auf dem der Spieler entschieden hat.
    public let stateVersion: Int
    public let action: TableAction

    public init(actionID: UUID = UUID(), stateVersion: Int, action: TableAction) {
        self.actionID = actionID
        self.stateVersion = stateVersion
        self.action = action
    }
}

public struct ActionResult: Codable, Equatable {
    public let actionID: UUID
    public let accepted: Bool
    public let reason: String?

    public init(actionID: UUID, accepted: Bool, reason: String?) {
        self.actionID = actionID
        self.accepted = accepted
        self.reason = reason
    }
}

// MARK: - Nachrichten

public struct HelloRequest: Codable, Equatable {
    public let token: String?
    public let displayName: String
    public let protocolVersion: Int

    public init(token: String?, displayName: String, protocolVersion: Int = blackCasinoProtocolVersion) {
        self.token = token
        self.displayName = displayName
        self.protocolVersion = protocolVersion
    }
}

public enum ClientMessage: Codable, Equatable {
    case hello(HelloRequest)
    case rename(displayName: String)
    case addFriend(friendCode: String)
    case removeFriend(playerID: String)
    case createRoom(game: OnlineGame)
    case joinRoom(code: String)
    case setRoomGame(game: OnlineGame)
    case startRoom
    case leaveRoom
    case inviteFriend(playerID: String)
    case findMatch(game: OnlineGame)
    case matchWithBots
    case keepWaiting
    case cancelMatch
    case tableAction(TableActionRequest)
    case leaveTable
    case claimOnlineRescue
    case ping
}

public enum ServerErrorCode: String, Codable, Equatable {
    case notAuthenticated, protocolMismatch, invalidRequest
    case roomNotFound, roomFull, roomAlreadyStarted, notHost, notEnoughPlayers, alreadyInRoom
    case friendNotFound, insufficientChips, notAtTable, rateLimited
}

public struct ServerError: Codable, Equatable {
    public let code: ServerErrorCode
    public let message: String

    public init(code: ServerErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ServerMessage: Codable, Equatable {
    case welcome(AccountInfo)
    case account(AccountInfo)
    case friends([FriendInfo])
    case room(RoomInfo?)
    case invitation(Invitation)
    case matchmaking(MatchmakingStatus)
    case table(TableSnapshot)
    case tableClosed(reason: String)
    case actionResult(ActionResult)
    case notice(String)
    case error(ServerError)
    case pong
}

// MARK: - Kodierung

public enum WireCodec {
    /// Maximale Nachrichtengröße (Schutz vor Missbrauch).
    public static let maxMessageBytes = 64 * 1024

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard text.utf8.count <= maxMessageBytes else { throw CocoaError(.coderInvalidValue) }
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
