import SwiftUI
import Observation

/// Zentraler App-Zustand: Profil, Speicherung, Belohnungen und Benachrichtigungen.
/// Spiele bewegen Chips ausschließlich über diese Klasse.
@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, start, lobby }

    var phase: Phase = .loading
    private(set) var profile: PlayerProfile
    private(set) var toasts: [Toast] = []
    var pendingLoginBonus: LoginBonusOffer?
    private(set) var storageWarning: String?

    /// Zufallsquelle für Karten und Walzen (kryptografisch sicher).
    /// Sie wird ausschließlich an die Spiel-Engines übergeben – nichts im Profil
    /// (Kontostand, Verlauf, Missionen, Erfolge) beeinflusst ihre Werte.
    @ObservationIgnored let random: RandomSource = SystemRandomSource()
    /// Getrennte Quelle für Nicht-Spiel-Zufall (Auswahl der Tagesmissionen, KI-Stil, Optik).
    @ObservationIgnored let auxiliaryRandom: RandomSource = SystemRandomSource()
    @ObservationIgnored private let store: ProfileStore?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        do {
            let store = try ProfileStore.defaultStore()
            let (profile, outcome) = store.load()
            self.store = store
            self.profile = profile
            if case .recoveredFromCorruption = outcome {
                storageWarning = "Der Spielstand war beschädigt und wurde zurückgesetzt."
            }
        } catch {
            store = nil
            profile = PlayerProfile()
            storageWarning = "Spielstand kann nicht gespeichert werden."
        }
        Haptics.isEnabled = profile.settings.hapticsEnabled
    }

    // MARK: - Lebenszyklus

    func launchFinished() {
        let refunded = profile.refundTableEscrow()
        if refunded > 0 {
            show(Toast(icon: "arrow.uturn.backward.circle.fill", title: "Unterbrochene Runde storniert",
                       subtitle: "\(ChipFormat.string(refunded)) Tisch-Chips wurden zurückgebucht"))
        }
        if let warning = storageWarning {
            show(Toast(icon: "exclamationmark.triangle.fill", title: "Hinweis", subtitle: warning, tint: Theme.red))
        }
        refreshDay()
        save()
    }

    func refreshDay() {
        profile.refreshDailyMissions(now: .now, random: auxiliaryRandom)
        pendingLoginBonus = profile.loginBonusOffer(now: .now)
    }

    // MARK: - Chips

    var chips: Int { profile.chips }

    /// Legt Chips auf den Tisch. Gibt `false` zurück (mit Hinweis), wenn der Kontostand nicht reicht.
    @discardableResult
    func moveToTable(_ amount: Int) -> Bool {
        do {
            try profile.moveToTable(amount)
            scheduleSave()
            return true
        } catch {
            Haptics.error()
            show(Toast(icon: "exclamationmark.circle.fill", title: "Nicht genug Chips",
                       subtitle: "Hol dir deine tägliche Belohnung im Menü.", tint: Theme.red))
            return false
        }
    }

    func releaseFromTable(stake: Int, payout: Int) {
        profile.releaseFromTable(stake: stake, payout: payout)
        scheduleSave()
    }

    func setTableEscrow(_ amount: Int) {
        profile.setTableEscrow(amount)
        scheduleSave()
    }

    /// Direktes Abbuchen (Slots: das Ergebnis steht sofort fest).
    @discardableResult
    func debit(_ amount: Int) -> Bool {
        do {
            try profile.debit(amount)
            scheduleSave()
            return true
        } catch {
            Haptics.error()
            show(Toast(icon: "exclamationmark.circle.fill", title: "Nicht genug Chips",
                       subtitle: "Verringere den Einsatz oder hol dir eine Belohnung.", tint: Theme.red))
            return false
        }
    }

    func credit(_ amount: Int) {
        profile.credit(amount)
        scheduleSave()
    }

    // MARK: - Fortschritt

    func record(_ event: GameEvent) {
        let notes = profile.record(event)
        present(notes)
        scheduleSave()
    }

    func claimLoginBonus() {
        guard let offer = try? profile.claimLoginBonus(now: .now) else { return }
        pendingLoginBonus = nil
        Haptics.success()
        show(Toast(icon: "gift.fill", title: "Login-Bonus Tag \(offer.streakDay)",
                   subtitle: "+\(ChipFormat.string(offer.amount)) Chips"))
        present(profile.checkAchievements())
        save()
    }

    var canClaimDailyReward: Bool { profile.canClaimDailyReward(now: .now) }

    func claimDailyReward() {
        guard let amount = try? profile.claimDailyReward(now: .now) else { return }
        Haptics.success()
        show(Toast(icon: "gift.fill", title: "Tägliche Belohnung", subtitle: "+\(ChipFormat.string(amount)) Chips"))
        save()
    }

    var canClaimRescue: Bool { profile.canClaimRescue(now: .now) }

    func claimRescue() {
        guard let amount = try? profile.claimRescue(now: .now) else { return }
        Haptics.success()
        show(Toast(icon: "lifepreserver.fill", title: "Startpaket", subtitle: "+\(ChipFormat.string(amount)) Chips"))
        save()
    }

    func claimMission(_ id: String) {
        guard let def = RewardTable.mission(id), let notes = try? profile.claimMission(id) else { return }
        Haptics.success()
        show(Toast(icon: "checkmark.seal.fill", title: "Mission eingelöst",
                   subtitle: "+\(ChipFormat.string(def.rewardChips)) Chips"))
        present(notes)
        save()
    }

    func claimAchievement(_ id: String) {
        guard let amount = try? profile.claimAchievement(id) else { return }
        Haptics.success()
        show(Toast(icon: "trophy.fill", title: "Belohnung erhalten", subtitle: "+\(ChipFormat.string(amount)) Chips"))
        save()
    }

    func isTutorialCompleted(_ game: GameKind) -> Bool {
        profile.completedTutorials.contains(game.rawValue)
    }

    func completeTutorial(_ game: GameKind) {
        let reward = profile.completeTutorial(game)
        guard reward > 0 else { return }
        Haptics.success()
        show(Toast(icon: "graduationcap.fill", title: "Tutorial abgeschlossen",
                   subtitle: "+\(ChipFormat.string(reward)) Chips Startbonus"))
        save()
    }

    // MARK: - Einstellungen

    func updateSettings(_ change: (inout PlayerSettings) -> Void) {
        change(&profile.settings)
        Haptics.isEnabled = profile.settings.hapticsEnabled
        scheduleSave()
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.displayName = String(trimmed.prefix(20))
        scheduleSave()
    }

    func resetProgress() {
        profile = PlayerProfile()
        try? store?.reset()
        refreshDay()
        save()
        show(Toast(icon: "arrow.counterclockwise", title: "Fortschritt zurückgesetzt",
                   subtitle: "Du startest wieder mit \(ChipFormat.string(PlayerProfile.startingChips)) Chips."))
    }

    // MARK: - Benachrichtigungen

    func show(_ toast: Toast) {
        toasts.append(toast)
        if toasts.count > 3 { toasts.removeFirst() }
        let id = toast.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            self?.toasts.removeAll { $0.id == id }
        }
    }

    private func present(_ notes: [ProgressNotification]) {
        for note in notes {
            switch note {
            case let .missionCompleted(def):
                show(Toast(icon: "flag.checkered", title: "Mission erfüllt", subtitle: def.title + " – jetzt einlösen"))
            case let .achievementUnlocked(def):
                show(Toast(icon: def.icon, title: "Erfolg: \(def.title)", subtitle: "Belohnung unter „Achievements“ abholen"))
            }
        }
    }

    // MARK: - Speichern

    /// Bündelt viele kleine Änderungen zu einem Schreibvorgang.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard let store else { return }
        do {
            try store.save(profile)
        } catch {
            storageWarning = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
