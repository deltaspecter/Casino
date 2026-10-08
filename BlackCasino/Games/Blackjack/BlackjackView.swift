import SwiftUI
import CasinoCore

struct BlackjackView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: BlackjackViewModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel {
                BlackjackScreen(viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = BlackjackViewModel(app: model) }
        }
    }
}

private struct BlackjackScreen: View {
    @Environment(AppModel.self) private var model
    let viewModel: BlackjackViewModel
    @State private var showTutorial = false
    @State private var showRules = false

    var body: some View {
        // Der Tisch bekommt den Raum oberhalb der Leiste – Informationen liegen nie über den Karten.
        VStack(spacing: 0) {
            SceneContainer(stage: viewModel.table.stage)
                .ignoresSafeArea(edges: [.top, .horizontal])
                .overlay(alignment: .top) {
                    GameTopBar(title: "BLACKJACK",
                               subtitle: "1 Deck, jede Runde neu gemischt · Dealer steht auf 17 · Blackjack 3:2",
                               showsBalance: false,
                               onLeave: { viewModel.leave() },
                               onRules: { showRules = true },
                               onHelp: { showTutorial = true })
                }
            TableBar {
                infoRow
            } controls: {
                controls
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.stage)
        .background(Color.black)
        .onAppear {
            if !model.isTutorialCompleted(.blackjack) { showTutorial = true }
        }
        .onDisappear { viewModel.leave() }
        .sheet(isPresented: $showTutorial) { TutorialSheet(game: .blackjack) }
        .sheet(isPresented: $showRules) { RulesSheet(game: .blackjack) }
    }

    // MARK: - Informationen (unter dem Tisch, nie über den Karten)

    @ViewBuilder private var infoRow: some View {
        InfoItem(title: "Virtuelle Chips", value: ChipFormat.string(model.chips))
        InfoItem(title: "Einsatz", value: ChipFormat.string(currentStake))
        if let dealer = viewModel.dealerValueText {
            InfoItem(title: "Dealer", value: dealer)
        }
        ForEach(Array(viewModel.hands.enumerated()), id: \.element.id) { index, hand in
            if !hand.cards.isEmpty {
                InfoItem(title: viewModel.hands.count > 1 ? "Hand \(index + 1)" : "Deine Hand",
                         value: hand.result?.outcome.title ?? hand.value.display,
                         highlighted: hand.isActive,
                         valueColor: hand.value.total > 21 ? Theme.redBright : .white)
            }
        }
        Spacer(minLength: 0)
        if let summary = viewModel.summary, viewModel.stage == .roundOver {
            ResultPill(title: summary.title, net: summary.net)
        }
    }

    private var currentStake: Int {
        viewModel.stage == .betting ? viewModel.pendingBet : viewModel.hands.reduce(0) { $0 + $1.bet }
    }

    // MARK: - Steuerung

    @ViewBuilder private var controls: some View {
        switch viewModel.stage {
        case .betting:
            bettingControls
        case .playerTurn, .busy:
            actionControls
        case .roundOver:
            HStack(spacing: 14) {
                Button("NEUE RUNDE") { Task { await viewModel.newRound() } }
                    .buttonStyle(.casino(.secondary, size: .large, fullWidth: true))
                Button("GLEICHER EINSATZ · \(ChipFormat.string(viewModel.lastBet))") {
                    Task {
                        viewModel.repeatLastBet()
                        await viewModel.deal()
                    }
                }
                .buttonStyle(.casino(.primary, size: .large, fullWidth: true))
                .disabled(model.chips < viewModel.rules.minBet)
            }
        }
    }

    private var bettingControls: some View {
        let chips = ChipSelector(values: BlackjackViewModel.chipValues,
                                 enabled: { $0 <= model.chips - viewModel.pendingBet },
                                 onTap: { viewModel.addChip($0) })
        let buttons = HStack(spacing: 12) {
            Button { viewModel.clearBet() } label: { Image(systemName: "xmark") }
                .buttonStyle(.casino(.ghost, size: .large))
                .disabled(viewModel.pendingBet == 0)
                .accessibilityLabel("Einsatz löschen")
            Button("DEAL") { Task { await viewModel.deal() } }
                .buttonStyle(.casino(.primary, size: .large))
                .disabled(viewModel.pendingBet < viewModel.rules.minBet)
        }
        // Breit: eine Zeile · schmal (Hochformat, iPad mini): zwei Zeilen
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { chips; Spacer(minLength: 0); limits; buttons }
            VStack(spacing: 12) { chips; HStack { limits; Spacer(); buttons } }
        }
        .overlay(alignment: .top) {
            if model.chips < viewModel.rules.minBet && viewModel.pendingBet == 0 {
                RescueHint().offset(y: -84)
            }
        }
    }

    private var limits: some View {
        Text("Min \(viewModel.rules.minBet) · Max \(ChipFormat.string(viewModel.rules.maxBet))")
            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            .fixedSize()
    }

    private var actionControls: some View {
        let enabled = viewModel.stage == .playerTurn
        return HStack(spacing: 12) {
            actionButton("HIT", icon: "plus", action: .hit, kind: .primary, enabled: enabled)
            actionButton("STAND", icon: "hand.raised.fill", action: .stand, kind: .secondary, enabled: enabled)
            actionButton("DOUBLE", icon: "arrow.up.square", action: .double, kind: .gold, enabled: enabled)
            actionButton("SPLIT", icon: "arrow.left.and.right", action: .split, kind: .secondary, enabled: enabled)
        }
    }

    private func actionButton(_ title: String, icon: String, action: BlackjackAction,
                              kind: CasinoButtonStyle.Kind, enabled: Bool) -> some View {
        let available = enabled && viewModel.actions.contains(action) && viewModel.canAfford(action)
        return Button {
            Task { await viewModel.perform(action) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold))
                Text(title)
            }
        }
        .buttonStyle(.casino(kind, size: .large, fullWidth: true))
        .disabled(!available)
    }
}

/// Hinweis, wenn der Kontostand nicht mehr für den Mindesteinsatz reicht.
struct RescueHint: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lifepreserver.fill").foregroundStyle(Theme.gold)
            Text(model.canClaimRescue ? "Zu wenig Chips? Hol dir ein kostenloses Startpaket." : "Tägliche Belohnung und Missionen bringen neue Chips.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            if model.canClaimRescue {
                Button("+\(ChipFormat.string(RewardTable.rescueAmount))") { model.claimRescue() }
                    .buttonStyle(.casino(.gold, size: .small))
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 20)
    }
}
