import SwiftUI
import CasinoCore

/// Einstellungen sowie Hinweise zu Zufall, Fairness und virtuellen Chips.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SheetHeader(title: "SETTINGS", subtitle: "Profil, Darstellung und Informationen")

                SectionTitle(title: "Spielername")
                TextField("Name", text: $name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { model.rename(name) }
                    .padding(18)
                    .glassPanel(cornerRadius: 18)

                SectionTitle(title: "Darstellung")
                VStack(spacing: 0) {
                    Toggle("Haptisches Feedback", isOn: Binding(
                        get: { model.profile.settings.hapticsEnabled },
                        set: { value in model.updateSettings { $0.hapticsEnabled = value } }))
                        .padding(18)
                    Divider().overlay(Theme.stroke)
                    Toggle("Reduzierte Effekte (schneller, akkuschonend; gilt ab dem nächsten Tisch)", isOn: Binding(
                        get: { model.profile.settings.reducedMotion },
                        set: { value in model.updateSettings { $0.reducedMotion = value } }))
                        .padding(18)
                }
                .tint(Theme.red)
                .foregroundStyle(.white)
                .glassPanel(cornerRadius: 22)

                SectionTitle(title: "Fairness & Zufall")
                infoBlock(icon: "dice.fill", text: "Ablauf jeder Runde: Zufallsgenerator → Mischen bzw. Walzenstopp → Ausgabe → Spielregeln → Ergebnis. Verwendet wird der kryptografisch sichere Zufallsgenerator des Systems; Karten werden per Fisher-Yates gemischt.")
                infoBlock(icon: "lock.shield.fill", text: "Es gibt keine Gewinn- oder Verlustserien-Steuerung, keine Anpassung an Kontostand, Verlauf, Uhrzeit, Missionen, Erfolge oder Daily Rewards. Die Spiel-Engines kennen dein Profil nicht.")
                infoBlock(icon: "film", text: "Animationen zeigen nur Ergebnisse an, die vorher von der Spiel-Engine berechnet wurden. Sie entscheiden nichts.")
                infoBlock(icon: "cpu", text: "Poker-Gegner sehen nur ihre eigenen Karten und das Board und können die Kartenverteilung nicht beeinflussen.")

                SectionTitle(title: "Virtuelle Chips")
                infoBlock(icon: "info.circle.fill", text: "BlackCasino ist ein reines Unterhaltungsspiel. Chips sind virtuell und haben keinen realen Geldwert. Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen und keinen Umtausch in Geld, Kryptowährungen oder Sachwerte.")
                infoBlock(icon: "arrow.uturn.backward.circle", text: "Wird die App während einer Runde beendet, wird die unterbrochene Runde storniert und der Einsatz beim nächsten Start zurückgebucht.")

                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Fortschritt zurücksetzen", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.casino(.ghost, size: .medium))
                .confirmationDialog("Gesamten Fortschritt löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Zurücksetzen", role: .destructive) {
                        model.resetProgress()
                        name = model.profile.displayName
                    }
                } message: {
                    Text("Kontostand, Statistik, Missionen und Erfolge werden auf den Anfang gesetzt (\(ChipFormat.string(PlayerProfile.startingChips)) Chips).")
                }

                Text("BlackCasino \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            .padding(32)
        }
        .onAppear { name = model.profile.displayName }
        .onDisappear { model.rename(name) }
    }

    private func infoBlock(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.gold).frame(width: 30)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }
}
