import SwiftUI
import CasinoCore

/// Kopfzeile für alle Spiele: Zurück, Titel, Kontostand, Hilfe.
struct GameTopBar: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    /// Optional abweichender Anzeige-Kontostand (z. B. solange Slot-Walzen noch drehen).
    var balance: Int?
    var onLeave: () -> Void = {}
    var onRules: (() -> Void)?
    var onHelp: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            BackButton(beforeLeaving: onLeave)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.display(22))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            ChipBalanceView(amount: balance ?? model.chips)
            if let onRules {
                Button {
                    Haptics.tap()
                    onRules()
                } label: {
                    Label("RULES", systemImage: "book.closed.fill")
                }
                .buttonStyle(.casino(.secondary, size: .small))
            }
            if let onHelp {
                IconButton(systemName: "questionmark", action: onHelp)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
    }
}

/// Auswahl der Chip-Werte für den Einsatz.
struct ChipSelector: View {
    let values: [Int]
    let enabled: (Int) -> Bool
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(values, id: \.self) { value in
                Button {
                    onTap(value)
                } label: {
                    ChipIcon(color: Self.color(for: value), size: 62)
                        .overlay(
                            Text(ChipFormat.compact(value))
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(Self.textColor(for: value))
                        )
                }
                .buttonStyle(ChipPressStyle())
                .disabled(!enabled(value))
                .opacity(enabled(value) ? 1 : 0.35)
                .accessibilityLabel("Chip \(value)")
            }
        }
    }

    static func color(for value: Int) -> Color {
        let d = ChipDenomination(rawValue: value) ?? .hundred
        return Color(uiColor: d.baseColor)
    }

    static func textColor(for value: Int) -> Color {
        let d = ChipDenomination(rawValue: value) ?? .hundred
        return Color(uiColor: d.textColor)
    }
}

private struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Ergebnis-Banner nach einer Runde.
struct ResultBanner: View {
    let title: String
    let net: Int
    let isWin: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.display(40))
                .foregroundStyle(isWin ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.white))
                .shadow(color: isWin ? Theme.gold.opacity(0.6) : .black, radius: 18)
            Text(ChipFormat.signed(net))
                .font(.numeric(26, weight: .heavy))
                .foregroundStyle(net > 0 ? Theme.success : net < 0 ? Theme.redBright : Theme.textSecondary)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .glassPanel(cornerRadius: 26)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Kleines Label im 3D-Raum (Handwert, Spielername …).
struct FloatingTag: View {
    let text: String
    var detail: String?
    var highlighted = false

    var body: some View {
        VStack(spacing: 1) {
            Text(text)
                .font(.numeric(18, weight: .black))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(highlighted ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Color.black.opacity(0.65)))
        )
        .overlay(Capsule().strokeBorder(highlighted ? Theme.goldLight.opacity(0.7) : Color.white.opacity(0.15)))
        .shadow(color: highlighted ? Theme.red.opacity(0.6) : .black.opacity(0.4), radius: 10)
        .fixedSize()
    }
}

// MARK: - Tutorials

struct TutorialPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let text: String
}

enum Tutorials {
    static func pages(for game: GameKind) -> [TutorialPage] {
        switch game {
        case .blackjack:
            return [
                TutorialPage(icon: "target", title: "Ziel", text: "Komm näher an 21 als der Dealer, ohne 21 zu überschreiten. Bildkarten zählen 10, Asse 1 oder 11."),
                TutorialPage(icon: "hand.tap.fill", title: "Aktionen", text: "Hit: weitere Karte · Stand: stehen bleiben · Double: Einsatz verdoppeln, genau eine Karte · Split: Paar in zwei Hände teilen."),
                TutorialPage(icon: "person.fill", title: "Dealer-Regeln", text: "Der Dealer zieht bis 17 und steht auf allen 17. Ein Blackjack (Ass + 10er) zahlt 3:2."),
                TutorialPage(icon: "shuffle", title: "Fair & zufällig", text: "Gespielt wird mit einem 52-Karten-Deck, das vor jeder Runde per Fisher-Yates mit einem kryptografisch sicheren Zufallsgenerator neu gemischt wird. Nichts ist vorherbestimmt.")
            ]
        case .poker:
            return [
                TutorialPage(icon: "suit.spade.fill", title: "Texas Hold'em", text: "Du erhältst zwei verdeckte Karten. Fünf Gemeinschaftskarten kommen in drei Schritten: Flop, Turn, River."),
                TutorialPage(icon: "list.number", title: "Handränge", text: "Royal Flush › Straight Flush › Vierling › Full House › Flush › Straße › Drilling › Zwei Paare › Paar › High Card."),
                TutorialPage(icon: "slider.horizontal.3", title: "Setzen", text: "Fold: aussteigen · Check: schieben · Call: mitgehen · Raise: erhöhen. Der Schieberegler bestimmt die Höhe."),
                TutorialPage(icon: "cpu", title: "Faire KI", text: "Die Gegner sehen nur ihre eigenen Karten und das Board – genau wie du. Jeder hat einen eigenen Spielstil.")
            ]
        case .slots:
            return [
                TutorialPage(icon: "rectangle.split.3x3", title: "5 Walzen, 10 Linien", text: "Gewinne zählen von links nach rechts auf aktiven Linien – ab drei gleichen Symbolen."),
                TutorialPage(icon: "star.fill", title: "Wild & Scatter", text: "Wild ersetzt alle normalen Symbole. Scatter zahlen überall auf den Walzen, multipliziert mit dem Gesamteinsatz."),
                TutorialPage(icon: "dice.fill", title: "Unabhängige Drehungen", text: "Jede Walze stoppt an einer zufälligen Position. Keine Serien, keine Steuerung – die Auszahlungsquote ist offen einsehbar.")
            ]
        }
    }
}

struct TutorialSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: GameKind
    @State private var index = 0

    var body: some View {
        let pages = Tutorials.pages(for: game)
        VStack(spacing: 28) {
            HStack {
                Text("SO FUNKTIONIERT \(game.title.uppercased())")
                    .font(.display(16, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)
                Spacer()
                IconButton(systemName: "xmark", size: 40) { dismiss() }
            }

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    VStack(spacing: 22) {
                        Image(systemName: page.icon)
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(Theme.redGradient)
                            .frame(width: 120, height: 120)
                            .background(Theme.red.opacity(0.12), in: Circle())
                        Text(page.title).font(.display(28)).foregroundStyle(.white)
                        Text(page.text)
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 380)

            if index == pages.count - 1 {
                Button {
                    model.completeTutorial(game)
                    dismiss()
                } label: {
                    Text(model.isTutorialCompleted(game) ? "LOS GEHT'S" : "VERSTANDEN · +\(ChipFormat.string(RewardTable.tutorialReward)) CHIPS")
                }
                .buttonStyle(.casino(.gold, size: .large))
            } else {
                Button("WEITER") { withAnimation { index += 1 } }
                    .buttonStyle(.casino(.primary, size: .large))
            }
        }
        .padding(32)
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(32)
    }
}
