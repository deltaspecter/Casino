import SwiftUI
import CasinoCore

/// Vollständiges, sichtbares Regelwerk für Blackjack und Poker.
/// (Die Slot-Regeln stehen pro Automat in `PaytableSheet`.)
struct RulesSheet: View {
    let game: GameKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeader(title: "RULES · \(game.title.uppercased())", subtitle: subtitle)
                switch game {
                case .blackjack: blackjackRules
                case .poker: pokerRules
                case .slots: EmptyView()
                }
                SectionTitle(title: "Zufall")
                RuleList(items: [
                    "Ablauf: Zufallsgenerator → Mischen → Kartenausgabe → Spielregeln → Ergebnis.",
                    "Gemischt wird ein vollständiges 52-Karten-Deck mit dem Fisher-Yates-Verfahren und dem kryptografisch sicheren Zufallsgenerator des Systems.",
                    "Keine Karte ist in einer Runde doppelt vorhanden.",
                    "Ergebnisse hängen nicht von Kontostand, Einsatzhöhe, vorherigen Runden, Missionen, Erfolgen oder Daily Rewards ab."
                ])
                NoCashValueNote()
            }
            .padding(32)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(32)
    }

    private var subtitle: String {
        game == .blackjack ? "Regelwerk dieses Tisches" : "No-Limit Texas Hold'em"
    }

    @ViewBuilder private var blackjackRules: some View {
        let rules = BlackjackViewModel.tableRules
        SectionTitle(title: "Tisch")
        RuleList(items: [
            "1 Standard-Deck mit 52 Karten, vor jeder Runde vollständig neu gemischt.",
            "Einsatz: \(rules.minBet) bis \(ChipFormat.string(rules.maxBet)) Chips pro Hand.",
            "Ausgabe: Spieler, Dealer (offen), Spieler, Dealer (verdeckt)."
        ])
        SectionTitle(title: "Kartenwerte")
        RuleList(items: [
            "2–10 zählen ihren Augenwert, Bube, Dame und König zählen 10.",
            "Ein Ass zählt 11 oder 1 – je nachdem, was die Hand nicht überkauft (Soft-Hand).",
            "Blackjack: Ass + 10er als erste zwei Karten (nicht nach einem Split)."
        ])
        SectionTitle(title: "Spieler")
        RuleList(items: [
            "Hit: weitere Karte · Stand: keine weitere Karte.",
            "Double Down: auf beliebige erste zwei Karten (auch nach Split) – Einsatz wird verdoppelt, genau eine weitere Karte.",
            "Split: zwei Karten gleichen Werts werden zu zwei Händen mit gleichem Einsatz, bis zu \(rules.maxHands) Hände.",
            "Geteilte Asse erhalten je genau eine Karte und können nicht erneut geteilt werden.",
            "Bei 21 endet die Hand automatisch. Keine Insurance, kein Surrender."
        ])
        SectionTitle(title: "Dealer")
        RuleList(items: [
            "Zeigt der Dealer ein Ass oder einen 10er, prüft er sofort auf Blackjack (Peek).",
            "Der Dealer zieht bis einschließlich 16 und steht auf allen 17 – auch auf Soft 17 (S17).",
            "Sind alle Spielerhände überkauft, zieht der Dealer keine weiteren Karten."
        ])
        SectionTitle(title: "Auszahlung")
        RuleList(items: [
            "Blackjack zahlt 3:2 (Einsatz 100 → 250 zurück).",
            "Gewinn zahlt 1:1 · Push (Gleichstand) gibt den Einsatz zurück.",
            "Bust (über 21) verliert immer – auch wenn der Dealer danach überkaufen würde.",
            "Spieler- und Dealer-Blackjack gleichzeitig: Push."
        ])
    }

    @ViewBuilder private var pokerRules: some View {
        SectionTitle(title: "Ablauf einer Hand")
        RuleList(items: [
            "Der Dealer-Button wandert pro Hand einen Platz weiter. Links davon zahlen Small Blind und Big Blind.",
            "Jeder Spieler erhält zwei verdeckte Hole Cards, reihum eine nach der anderen.",
            "Preflop: Setzrunde, beginnend links vom Big Blind (heads-up beginnt der Button).",
            "Flop: drei Gemeinschaftskarten, Turn: eine, River: eine – jeweils mit Burn-Karte und Setzrunde, beginnend links vom Button.",
            "Showdown: Die beste 5-Karten-Hand aus 2 Hole Cards und 5 Gemeinschaftskarten gewinnt."
        ])
        SectionTitle(title: "Aktionen")
        RuleList(items: [
            "Fold: aussteigen · Check: schieben, wenn kein Einsatz offen ist · Call: offenen Einsatz bezahlen.",
            "Bet: erster Einsatz einer Runde (mindestens Big Blind) · Raise: erhöhen, mindestens um die letzte Erhöhung.",
            "All-in: alle verbleibenden Chips. Wer All-in ist, kann nur den Teil des Pots gewinnen, den er abgedeckt hat (Side-Pots).",
            "Eine Setzrunde endet, wenn alle aktiven Spieler gehandelt und gleich viel gesetzt haben."
        ])
        SectionTitle(title: "Handrangfolge (höchste zuerst)")
        RuleList(items: [
            "Royal Flush – A K Q J 10 einer Farbe",
            "Straight Flush – fünf aufeinanderfolgende Karten einer Farbe",
            "Four of a Kind (Vierling)",
            "Full House – Drilling + Paar",
            "Flush – fünf Karten einer Farbe",
            "Straight (Straße) – fünf aufeinanderfolgende Karten; A-2-3-4-5 ist die niedrigste",
            "Three of a Kind (Drilling)",
            "Two Pair (Zwei Paare)",
            "One Pair (Ein Paar)",
            "High Card"
        ], numbered: true)
        SectionTitle(title: "Gleichstand")
        RuleList(items: [
            "Bei gleicher Kategorie entscheiden die Kartenwerte (Kicker) in Rangfolge; Farben zählen nie.",
            "Sind die besten fünf Karten gleichwertig, wird der Pot geteilt. Ein unteilbarer Rest-Chip geht an den ersten Gewinner links vom Button."
        ])
        SectionTitle(title: "KI-Gegner")
        RuleList(items: [
            "Die KI sieht nur ihre eigenen Karten, das Board, den Pot und die Einsätze.",
            "Sie schätzt ihre Chancen durch Simulation mit unbekannten Karten. Ihr Spielstil (vorsichtig, ausgewogen, aggressiv, Calling Station) beeinflusst nur ihre Entscheidungen – nie die Kartenverteilung."
        ])
    }
}

struct RuleList: View {
    let items: [String]
    var numbered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    if numbered {
                        Text("\(index + 1).")
                            .font(.numeric(15, weight: .heavy)).foregroundStyle(Theme.gold)
                            .frame(width: 26, alignment: .trailing)
                    } else {
                        Circle().fill(Theme.red).frame(width: 7, height: 7).padding(.top, 7)
                    }
                    Text(item)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }
}
