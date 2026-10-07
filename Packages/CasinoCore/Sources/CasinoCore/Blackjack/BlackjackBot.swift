import Foundation

/// Strategie für Blackjack-Bot-Spieler an Online-Tischen.
///
/// Der Bot entscheidet ausschließlich anhand von Informationen, die jeder Spieler am Tisch sieht:
/// seine eigene Hand und die offene Dealer-Karte. Er kennt weder die verdeckte Dealer-Karte
/// noch die Reihenfolge des Decks und hat keinen Zugriff auf den Zufallsgenerator.
/// Gespielt wird eine vereinfachte Grundstrategie (Basic Strategy, S17).
public enum BlackjackBot {
    public static func decide(hand: BlackjackHand, dealerUpcard: Card, available: Set<BlackjackAction>) -> BlackjackAction {
        let up = dealerUpcard.rank.blackjackValue == 11 ? 11 : dealerUpcard.rank.blackjackValue
        let value = hand.value

        // Paare
        if available.contains(.split), hand.cards.count == 2 {
            let pair = hand.cards[0].rank.blackjackValue
            switch pair {
            case 11, 8: return .split
            case 9 where ![7, 10, 11].contains(up): return .split
            case 7 where up <= 7, 6 where (2...6).contains(up), 3 where (4...7).contains(up), 2 where (4...7).contains(up):
                return .split
            default: break
            }
        }

        // Soft-Hände
        if value.isSoft {
            switch value.total {
            case 19...: return .stand
            case 18:
                if available.contains(.double) && (3...6).contains(up) { return .double }
                return up >= 9 ? .hit : .stand
            case 17:
                if available.contains(.double) && (3...6).contains(up) { return .double }
                return .hit
            case 15, 16:
                if available.contains(.double) && (4...6).contains(up) { return .double }
                return .hit
            default:
                if available.contains(.double) && (5...6).contains(up) { return .double }
                return .hit
            }
        }

        // Harte Hände
        switch value.total {
        case 17...: return .stand
        case 13...16: return up <= 6 ? .stand : .hit
        case 12: return (4...6).contains(up) ? .stand : .hit
        case 11: return available.contains(.double) ? .double : .hit
        case 10: return available.contains(.double) && up <= 9 ? .double : .hit
        case 9: return available.contains(.double) && (3...6).contains(up) ? .double : .hit
        default: return .hit
        }
    }
}
