import Foundation
import Crypto
import CasinoNet

/// Online-Konto. Der Server ist die einzige Quelle für Online-Chips.
struct Account: Codable, Equatable {
    let id: String
    var displayName: String
    let friendCode: String
    /// SHA-256 des Zugangstokens (das Token selbst wird nie gespeichert).
    let tokenHash: String
    /// Frei verfügbare Online-Chips.
    var chips: Int
    /// Chips, die gerade auf einem Tisch liegen (Einsätze, Poker-Stack).
    var tableChips: Int
    var friends: Set<String>
    var lastRescue: Date?
    let createdAt: Date

    var info: PlayerInfo { PlayerInfo(id: id, displayName: displayName, friendCode: friendCode) }
}

enum WalletError: Error, Equatable {
    case insufficientChips
    case invalidAmount
    case unknownAccount
}

/// Konten, Tokens, Freunde und Online-Chips. Wird ausschließlich innerhalb des
/// `GameServer`-Actors verwendet – alle Zugriffe sind dadurch serialisiert.
final class AccountStore {
    static let startingChips = 10_000
    static let rescueAmount = 2_500
    static let rescueThreshold = 100
    static let rescueCooldown: TimeInterval = 3_600

    private(set) var accounts: [String: Account] = [:]
    private var byTokenHash: [String: String] = [:]
    private var byFriendCode: [String: String] = [:]
    private let fileURL: URL?
    private var dirty = false

    /// - Parameter fileURL: JSON-Datei zur Speicherung; `nil` = nur im Speicher (Tests).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - Registrierung & Anmeldung

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sanitize(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
        return trimmed.isEmpty ? "Spieler" : String(trimmed.prefix(20))
    }

    func register(displayName: String, now: Date = Date()) -> (Account, token: String) {
        let token = Self.makeToken()
        var friendCode: String
        repeat { friendCode = RoomCode.generate() } while byFriendCode[friendCode] != nil
        let account = Account(id: UUID().uuidString, displayName: Self.sanitize(name: displayName),
                              friendCode: friendCode, tokenHash: Self.hash(token),
                              chips: Self.startingChips, tableChips: 0, friends: [], lastRescue: nil, createdAt: now)
        accounts[account.id] = account
        byTokenHash[account.tokenHash] = account.id
        byFriendCode[friendCode] = account.id
        markDirty()
        return (account, token)
    }

    func authenticate(token: String) -> Account? {
        byTokenHash[Self.hash(token)].flatMap { accounts[$0] }
    }

    func account(_ id: String) -> Account? { accounts[id] }

    func account(friendCode: String) -> Account? {
        RoomCode.normalize(friendCode).flatMap { byFriendCode[$0] }.flatMap { accounts[$0] }
    }

    func rename(_ id: String, to name: String) {
        accounts[id]?.displayName = Self.sanitize(name: name)
        markDirty()
    }

    // MARK: - Wallet (niemals negativ)

    /// Bucht Chips vom freien Guthaben auf den Tisch.
    func moveToTable(_ id: String, amount: Int) throws {
        guard amount > 0 else { throw WalletError.invalidAmount }
        guard var account = accounts[id] else { throw WalletError.unknownAccount }
        guard account.chips >= amount else { throw WalletError.insufficientChips }
        account.chips -= amount
        account.tableChips += amount
        accounts[id] = account
        markDirty()
    }

    /// Gibt Tisch-Chips frei: `stake` verlässt den Tisch, `payout` geht auf das Guthaben.
    func releaseFromTable(_ id: String, stake: Int, payout: Int) {
        guard var account = accounts[id] else { return }
        account.tableChips = max(0, account.tableChips - max(0, stake))
        account.chips += max(0, payout)
        accounts[id] = account
        markDirty()
    }

    /// Verändert den Tischbetrag um Gewinn/Verlust einer Poker-Hand (Chips wechseln am Tisch den Besitzer).
    func adjustTableChips(_ id: String, by delta: Int) {
        guard accounts[id] != nil else { return }
        accounts[id]!.tableChips = max(0, accounts[id]!.tableChips + delta)
        markDirty()
    }

    /// Nach einem Serverneustart existieren keine Tische mehr: alle Tisch-Chips zurückbuchen.
    func refundAllTableChips() {
        for id in accounts.keys where accounts[id]!.tableChips > 0 {
            accounts[id]!.chips += accounts[id]!.tableChips
            accounts[id]!.tableChips = 0
            markDirty()
        }
    }

    func claimRescue(_ id: String, now: Date = Date()) -> Bool {
        guard var account = accounts[id], account.chips + account.tableChips < Self.rescueThreshold else { return false }
        if let last = account.lastRescue, now.timeIntervalSince(last) < Self.rescueCooldown { return false }
        account.chips += Self.rescueAmount
        account.lastRescue = now
        accounts[id] = account
        markDirty()
        return true
    }

    // MARK: - Freunde (gegenseitig)

    func addFriend(_ id: String, friendID: String) {
        guard id != friendID, accounts[id] != nil, accounts[friendID] != nil else { return }
        accounts[id]!.friends.insert(friendID)
        accounts[friendID]!.friends.insert(id)
        markDirty()
    }

    func removeFriend(_ id: String, friendID: String) {
        accounts[id]?.friends.remove(friendID)
        accounts[friendID]?.friends.remove(id)
        markDirty()
    }

    // MARK: - Speicherung

    private func markDirty() { dirty = true }

    /// Schreibt Änderungen atomar auf die Platte.
    func saveIfNeeded() {
        guard dirty, let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(accounts.values))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch {
            print("[AccountStore] Speichern fehlgeschlagen: \(error)")
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([Account].self, from: data) else {
            // Beschädigte Datei sichern statt sie zu überschreiben.
            let backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            print("[AccountStore] Konten-Datei unlesbar – gesichert unter \(backup.lastPathComponent)")
            return
        }
        for var account in list {
            account.chips = max(0, account.chips)
            account.tableChips = max(0, account.tableChips)
            accounts[account.id] = account
            byTokenHash[account.tokenHash] = account.id
            byFriendCode[account.friendCode] = account.id
        }
    }
}
