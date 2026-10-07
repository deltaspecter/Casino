import Foundation

/// Speichert den Spielstand als JSON (atomar geschrieben).
/// Ist die Datei beschädigt, wird sie als Backup zur Seite gelegt und ein neues Profil erstellt,
/// statt die App abstürzen zu lassen.
public final class ProfileStore {
    public enum LoadOutcome: Equatable {
        case loaded
        case created
        case recoveredFromCorruption(backup: URL)
    }

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Standardpfad: `Application Support/BlackCasino/profile.json`.
    public static func defaultStore() throws -> ProfileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("BlackCasino", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(fileURL: dir.appendingPathComponent("profile.json"))
    }

    public func load() -> (PlayerProfile, LoadOutcome) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (PlayerProfile(), .created)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let profile = try decoder.decode(PlayerProfile.self, from: data)
            return (profile, .loaded)
        } catch {
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return (PlayerProfile(), .recoveredFromCorruption(backup: backup))
        }
    }

    public func save(_ profile: PlayerProfile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
