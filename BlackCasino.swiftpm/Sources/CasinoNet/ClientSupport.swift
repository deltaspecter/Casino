import Foundation

/// Raumcodes: 6 Zeichen ohne leicht verwechselbare Zeichen (kein 0/O, 1/I).
public enum RoomCode {
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let length = 6

    /// Normalisiert eine Benutzereingabe (Leerzeichen, Kleinbuchstaben, Bindestriche) oder gibt `nil` zurück.
    public static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// Erzeugt einen zufälligen Code (kryptografisch sicherer Systemgenerator).
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

/// Verhindert doppelte Aktionen: Solange eine Aktion unbestätigt ist, wird keine weitere gesendet.
public struct ActionGate: Equatable {
    public private(set) var pendingActionID: UUID?
    public private(set) var pendingSince: Date?

    public init() {}

    public var isBusy: Bool { pendingActionID != nil }

    /// Beginnt eine Aktion und liefert deren ID – oder `nil`, wenn bereits eine Aktion läuft.
    public mutating func begin(now: Date = Date()) -> UUID? {
        guard pendingActionID == nil else { return nil }
        let id = UUID()
        pendingActionID = id
        pendingSince = now
        return id
    }

    /// Server-Antwort zu einer Aktion erhalten.
    public mutating func resolve(_ actionID: UUID) {
        if pendingActionID == actionID { reset() }
    }

    /// Neuer Spielstand vom Server oder Verbindungsabbruch: offene Aktion verwerfen.
    public mutating func reset() {
        pendingActionID = nil
        pendingSince = nil
    }
}

/// Wartezeiten für Wiederverbindungsversuche (exponentiell, gedeckelt).
public struct ReconnectPolicy: Equatable {
    public let delays: [TimeInterval]

    public init(delays: [TimeInterval] = [0.5, 1, 2, 4, 8, 15, 15, 15]) {
        self.delays = delays
    }

    /// Gesamte Zeit, die maximal versucht wird (danach gilt die Verbindung als verloren).
    public var totalDuration: TimeInterval { delays.reduce(0, +) }

    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        attempt < delays.count ? delays[attempt] : nil
    }
}
