import SwiftUI
import CasinoCore

/// Übersicht aller Spielstatistiken. Reine Anzeige – keine Engine liest diese Werte.
struct StatisticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.profile.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SheetHeader(title: "STATISTICS", subtitle: "Dein bisheriges Spiel in Zahlen – nur zur Anzeige.")

                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(title: "Kontostand", value: ChipFormat.string(model.chips), accent: true)
                    StatTile(title: "Höchster Kontostand", value: ChipFormat.string(s.peakChips))
                    StatTile(title: "Größter Gewinn", value: ChipFormat.string(s.biggestWin))
                    StatTile(title: "Gespielte Runden", value: ChipFormat.string(s.gamesPlayed))
                }

                SectionTitle(title: "Gesamt")
                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(title: "Gesamtgewinne", value: ChipFormat.string(s.totalWon), valueColor: Theme.success)
                    StatTile(title: "Gesamtverluste", value: ChipFormat.string(s.totalLost), valueColor: Theme.redBright)
                    StatTile(title: "Saldo", value: ChipFormat.signed(s.netResult),
                             valueColor: s.netResult >= 0 ? Theme.success : Theme.redBright)
                    StatTile(title: "Gesetzt gesamt", value: ChipFormat.string(s.totalWagered))
                    StatTile(title: "Gewonnene Runden", value: ChipFormat.string(s.roundsWon))
                }

                SectionTitle(title: "Blackjack")
                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(title: "Runden", value: ChipFormat.string(s.blackjackRounds))
                    StatTile(title: "Hände (inkl. Split)", value: ChipFormat.string(s.blackjackHands))
                    StatTile(title: "Gewonnene Hände", value: ChipFormat.string(s.blackjackWins))
                    StatTile(title: "Push", value: ChipFormat.string(s.blackjackPushes))
                    StatTile(title: "Blackjacks", value: ChipFormat.string(s.blackjacks))
                }

                SectionTitle(title: "Poker")
                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(title: "Runden", value: ChipFormat.string(s.pokerHands))
                    StatTile(title: "Gewonnene Pots", value: ChipFormat.string(s.pokerWins))
                    StatTile(title: "Gewinnquote", value: percent(s.pokerWins, of: s.pokerHands))
                }

                SectionTitle(title: "Slots")
                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(title: "Spins", value: ChipFormat.string(s.slotSpins))
                    StatTile(title: "Gewinn-Spins", value: ChipFormat.string(s.slotWins))
                    StatTile(title: "Trefferquote", value: percent(s.slotWins, of: s.slotSpins))
                }

                NoCashValueNote()
                    .frame(maxWidth: .infinity)
            }
            .padding(32)
        }
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 190), spacing: 14)] }

    private func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        return String(format: "%.1f %%", Double(part) / Double(total) * 100).replacingOccurrences(of: ".", with: ",")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var accent = false
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.numeric(24, weight: .heavy))
                .foregroundStyle(accent ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(valueColor))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 18)
    }
}
