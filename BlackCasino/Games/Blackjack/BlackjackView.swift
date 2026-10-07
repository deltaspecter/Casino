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
        ZStack {
            SceneContainer(stage: viewModel.table.stage) { points in
                viewModel.anchors = points
            }
            .ignoresSafeArea()

            anchoredLabels
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                GameTopBar(title: "BLACKJACK",
                           subtitle: "1 Deck, jede Runde neu gemischt · Dealer steht auf 17 · Blackjack 3:2",
                           onLeave: { viewModel.leave() },
                           onRules: { showRules = true },
                           onHelp: { showTutorial = true })
                Spacer()
                if let summary = viewModel.summary, viewModel.stage == .roundOver {
                    ResultBanner(title: summary.title, net: summary.net, isWin: summary.isWin)
                        .padding(.bottom, 20)
                }
                controls
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 22)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.stage)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.summary)
        }
        .background(Color.black)
        .onAppear {
            if !model.isTutorialCompleted(.blackjack) { showTutorial = true }
        }
        .onDisappear { viewModel.leave() }
        .sheet(isPresented: $showTutorial) { TutorialSheet(game: .blackjack) }
        .sheet(isPresented: $showRules) { RulesSheet(game: .blackjack) }
    }

    // MARK: - 3D-Labels

    private var anchoredLabels: some View {
        ZStack {
            if let text = viewModel.dealerValueText, let point = viewModel.anchors["dealer"] {
                FloatingTag(text: text, detail: "DEALER")
                    .position(point)
            }
            ForEach(viewModel.hands) { hand in
                if !hand.cards.isEmpty, let point = viewModel.anchors["hand-\(hand.id)"] {
                    FloatingTag(text: hand.result?.outcome.title ?? hand.value.display,
                                detail: "Einsatz \(ChipFormat.string(hand.bet))",
                                highlighted: hand.isActive || hand.result?.outcome == .win || hand.result?.outcome == .blackjack)
                        .position(point)
                        .animation(.easeOut(duration: 0.2), value: point)
                }
            }
        }
    }

    // MARK: - Steuerung

    @ViewBuilder private var controls: some View {
        switch viewModel.stage {
        case .betting:
            bettingPanel
        case .playerTurn, .busy:
            actionPanel
        case .roundOver:
            HStack(spacing: 16) {
                Button("NEUE RUNDE") { Task { await viewModel.newRound() } }
                    .buttonStyle(.casino(.secondary, size: .large))
                Button("GLEICHER EINSATZ · \(ChipFormat.string(viewModel.lastBet))") {
                    Task {
                        viewModel.repeatLastBet()
                        await viewModel.deal()
                    }
                }
                .buttonStyle(.casino(.primary, size: .large))
                .disabled(model.chips < viewModel.rules.minBet)
            }
            .padding(18)
            .glassPanel(cornerRadius: 30)
        }
    }

    private var bettingPanel: some View {
        HStack(alignment: .center, spacing: 24) {
            ChipSelector(values: BlackjackViewModel.chipValues,
                         enabled: { $0 <= model.chips - viewModel.pendingBet },
                         onTap: { viewModel.addChip($0) })

            Divider().frame(height: 60).overlay(Theme.stroke)

            VStack(alignment: .leading, spacing: 2) {
                Text("EINSATZ").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textSecondary)
                Text(ChipFormat.string(viewModel.pendingBet))
                    .font(.numeric(30, weight: .black))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(viewModel.pendingBet)))
                    .animation(.snappy, value: viewModel.pendingBet)
                Text("Min \(viewModel.rules.minBet) · Max \(ChipFormat.string(viewModel.rules.maxBet))")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .frame(minWidth: 130, alignment: .leading)

            Spacer(minLength: 0)

            Button { viewModel.clearBet() } label: { Image(systemName: "xmark") }
                .buttonStyle(.casino(.ghost, size: .large))
                .disabled(viewModel.pendingBet == 0)
                .accessibilityLabel("Einsatz löschen")

            Button("DEAL") { Task { await viewModel.deal() } }
                .buttonStyle(.casino(.primary, size: .large))
                .disabled(viewModel.pendingBet < viewModel.rules.minBet)
        }
        .padding(18)
        .glassPanel(cornerRadius: 30)
        .overlay(alignment: .top) {
            if model.chips < viewModel.rules.minBet && viewModel.pendingBet == 0 {
                RescueHint().offset(y: -70)
            }
        }
    }

    private var actionPanel: some View {
        let enabled = viewModel.stage == .playerTurn
        return HStack(spacing: 14) {
            actionButton("HIT", icon: "plus", action: .hit, kind: .primary, enabled: enabled)
            actionButton("STAND", icon: "hand.raised.fill", action: .stand, kind: .secondary, enabled: enabled)
            actionButton("DOUBLE", icon: "arrow.up.square", action: .double, kind: .gold, enabled: enabled)
            actionButton("SPLIT", icon: "arrow.left.and.right", action: .split, kind: .secondary, enabled: enabled)
        }
        .padding(18)
        .glassPanel(cornerRadius: 30)
    }

    private func actionButton(_ title: String, icon: String, action: BlackjackAction,
                              kind: CasinoButtonStyle.Kind, enabled: Bool) -> some View {
        let available = enabled && viewModel.actions.contains(action) && viewModel.canAfford(action)
        return Button {
            Task { await viewModel.perform(action) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold))
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
