import SwiftUI
import CasinoCore

/// Profil, Statistiken, Einstellungen sowie Hinweise zu Zufall und virtuellen Chips.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var confirmReset = false

    var body: some View {
        let p = model.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SheetHeader(title: "PROFIL", subtitle: "Dein Fortschritt bei BlackCasino")

                HStack(spacing: 22) {
                    LevelBadge(level: p.level, progress: p.levelProgress, size: 96)
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Name", text: $name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { model.rename(name) }
                        ProgressBar(value: p.levelProgress)
                        Text("\(p.xp) / \(p.xpForNextLevel) XP bis Level \(p.level + 1) · Aufstieg: +\(ChipFormat.string(RewardTable.levelUpReward(newLevel: p.level + 1))) Chips")
                            .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(22)
                .glassPanel(cornerRadius: 26)

                SectionTitle(title: "Statistik")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    stat("Kontostand", ChipFormat.string(p.chips))
                    stat("Höchststand", ChipFormat.string(p.stats.peakChips))
                    stat("Größter Gewinn", ChipFormat.string(p.stats.biggestWin))
                    stat("Gesetzt gesamt", ChipFormat.string(p.stats.totalWagered))
                    stat("Blackjack-Hände", "\(p.stats.blackjackHands)")
                    stat("Blackjacks", "\(p.stats.blackjacks)")
                    stat("Poker-Hände", "\(p.stats.pokerHands)")
                    stat("Pots gewonnen", "\(p.stats.pokerWins)")
                    stat("Slot-Drehungen", "\(p.stats.slotSpins)")
                    stat("Login-Serie", "\(p.loginStreak) Tage")
                }

                SectionTitle(title: "Einstellungen")
                VStack(spacing: 0) {
                    Toggle("Haptisches Feedback", isOn: Binding(
                        get: { model.profile.settings.hapticsEnabled },
                        set: { value in model.updateSettings { $0.hapticsEnabled = value } }))
                        .padding(18)
                    Divider().overlay(Theme.stroke)
                    Toggle("Reduzierte Effekte (schont Akku, gilt ab nächstem Tisch)", isOn: Binding(
                        get: { model.profile.settings.reducedMotion },
                        set: { value in model.updateSettings { $0.reducedMotion = value } }))
                        .padding(18)
                }
                .tint(Theme.red)
                .foregroundStyle(.white)
                .glassPanel(cornerRadius: 22)

                SectionTitle(title: "Fairness & Zufall")
                infoBlock(icon: "dice.fill", text: "Alle Ergebnisse entstehen zur Laufzeit aus einem kryptografisch sicheren Zufallsgenerator des Systems. Karten werden mit dem Fisher-Yates-Verfahren gemischt, Slot-Walzen stoppen unabhängig an zufälligen Positionen. Es gibt keine vorherbestimmten Ergebnisse und keine Logik, die Gewinne oder Verluste steuert.")
                infoBlock(icon: "cpu", text: "Poker-Gegner sehen nur ihre eigenen Karten und das Board. Ihre Entscheidungen basieren auf Simulationen mit unbekannten Karten – sie schummeln nicht.")

                SectionTitle(title: "Virtuelle Chips")
                infoBlock(icon: "info.circle.fill", text: "BlackCasino ist ein reines Unterhaltungsspiel. Chips sind virtuell und haben keinen realen Geldwert. Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen und keinen Umtausch in Geld, Kryptowährungen oder Sachwerte.")

                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Fortschritt zurücksetzen", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.casino(.ghost, size: .medium))
                .confirmationDialog("Gesamten Fortschritt löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Zurücksetzen", role: .destructive) { model.resetProgress() }
                } message: {
                    Text("Chips, Level, Statistiken und Erfolge werden auf den Anfang gesetzt.")
                }
            }
            .padding(32)
        }
        .onAppear { name = model.profile.displayName }
        .onDisappear { model.rename(name) }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            Text(value).font(.numeric(22, weight: .heavy)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 18)
    }

    private func infoBlock(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.gold).frame(width: 30)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }
}
