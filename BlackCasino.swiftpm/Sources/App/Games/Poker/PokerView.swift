import SwiftUI

struct PokerView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: PokerViewModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel {
                PokerScreen(viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = PokerViewModel(app: model) }
        }
    }
}

private struct PokerScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var viewModel: PokerViewModel
    @State private var showTutorial = false
    @State private var showRules = false

    var body: some View {
        ZStack {
            // Tisch oberhalb der Leiste; Namensschilder liegen auf der Rail, nicht auf den Karten.
            VStack(spacing: 0) {
                SceneContainer(stage: viewModel.table.stage) { points in
                    viewModel.anchors = points
                }
                .ignoresSafeArea(edges: [.top, .horizontal])
                .overlay { seatOverlays.allowsHitTesting(false) }
                .overlay(alignment: .top) {
                    GameTopBar(title: "TEXAS HOLD'EM",
                               subtitle: "No Limit · Blinds \(viewModel.selectedTable.smallBlind)/\(viewModel.selectedTable.bigBlind)",
                               showsBalance: false,
                               onLeave: { viewModel.leave() },
                               onRules: { showRules = true },
                               onHelp: { showTutorial = true })
                }
                if viewModel.stage != .setup {
                    TableBar {
                        infoRow
                    } controls: {
                        HStack { Spacer(minLength: 0); controls }
                    }
                }
            }

            if viewModel.stage == .setup {
                setupOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.stage)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isHumanTurn)
        .onAppear {
            if !model.isTutorialCompleted(.poker) { showTutorial = true }
        }
        .onDisappear { viewModel.leave() }
        .sheet(isPresented: $showTutorial) { TutorialSheet(game: .poker) }
        .sheet(isPresented: $showRules) { RulesSheet(game: .poker) }
    }

    // MARK: - Sitz-Overlays

    private var seatOverlays: some View {
        ZStack {
            ForEach(viewModel.seats.filter { !$0.isHuman }) { seat in
                if let point = viewModel.anchors["seat-\(seat.id)"] {
                    SeatBadge(seat: seat,
                              action: viewModel.lastActions[seat.id],
                              isThinking: viewModel.thinkingSeatID == seat.id,
                              isButton: viewModel.buttonSeatID == seat.id,
                              revealedHand: viewModel.revealedSeats.contains(seat.id) ? viewModel.showdownHands[seat.id] : nil,
                              showCards: false)
                        .position(point)
                }
            }
        }
    }

    // MARK: - Unterer Bereich

    // MARK: - Informationen in der Leiste

    @ViewBuilder private var infoRow: some View {
        InfoItem(title: "Virtuelle Chips", value: ChipFormat.string(model.chips))
        InfoItem(title: "Dein Stack", value: ChipFormat.string(viewModel.human?.stack ?? 0))
        InfoItem(title: "Einsatz", value: ChipFormat.string(viewModel.human?.streetBet ?? 0))
        InfoItem(title: "Pot", value: ChipFormat.string(viewModel.pot))
        if let handName = viewModel.humanHandName, viewModel.human?.hasFolded == false {
            InfoItem(title: "Deine Hand", value: handName, valueColor: Theme.goldLight)
        }
        if let action = viewModel.lastActions[PokerViewModel.humanSeatID] {
            InfoItem(title: "Letzte Aktion", value: action)
        }
        Spacer(minLength: 0)
        if let text = viewModel.resultText, viewModel.stage != .playing {
            Text(text.components(separatedBy: "\n").first ?? text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(viewModel.humanWonLastHand ? Theme.goldLight : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var controls: some View {
        switch viewModel.stage {
        case .playing:
            if let legal = viewModel.legal {
                actionControls(legal)
            } else {
                Text(viewModel.thinkingSeatID != nil ? "Gegner überlegt …" : " ")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(height: 68)
            }
        case .handOver:
            HStack(spacing: 12) {
                Button("AUFSTOCKEN") { viewModel.topUp(viewModel.selectedTable.minBuyIn) }
                    .buttonStyle(.casino(.secondary, size: .large))
                    .disabled(model.chips < viewModel.selectedTable.minBuyIn)
                Button("NÄCHSTE HAND") { Task { await viewModel.nextHand() } }
                    .buttonStyle(.casino(.primary, size: .large))
            }
        case .busted:
            HStack(spacing: 12) {
                Button("NACHKAUFEN · \(ChipFormat.string(viewModel.selectedTable.minBuyIn))") {
                    viewModel.topUp(viewModel.selectedTable.minBuyIn)
                }
                .buttonStyle(.casino(.gold, size: .large))
                .disabled(model.chips < viewModel.selectedTable.minBuyIn)
            }
        case .setup:
            EmptyView()
        }
    }

    private func actionControls(_ legal: PokerLegalActions) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { raiseRow(legal); actionButtons(legal) }
            VStack(alignment: .trailing, spacing: 10) { raiseRow(legal); actionButtons(legal) }
        }
    }

    @ViewBuilder private func raiseRow(_ legal: PokerLegalActions) -> some View {
        if legal.canRaise && legal.maxRaiseTo > legal.minRaiseTo {
            HStack(spacing: 8) {
                quickRaise("MIN") { viewModel.raiseTarget = Double(legal.minRaiseTo) }
                quickRaise("½ POT") { viewModel.setRaise(potFraction: 0.5) }
                quickRaise("POT") { viewModel.setRaise(potFraction: 1) }
                Slider(value: $viewModel.raiseTarget,
                       in: Double(legal.minRaiseTo)...Double(legal.maxRaiseTo),
                       step: Double(max(1, min(viewModel.bigBlind, legal.maxRaiseTo - legal.minRaiseTo))))
                    .tint(Theme.red)
                    .frame(minWidth: 160, maxWidth: 240)
            }
        }
    }

    private func actionButtons(_ legal: PokerLegalActions) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack(spacing: 12) {
                Button("FOLD") { Task { await viewModel.act(.fold) } }
                    .buttonStyle(.casino(.secondary, size: .large))
                if legal.canCheck {
                    Button("CHECK") { Task { await viewModel.act(.check) } }
                        .buttonStyle(.casino(.secondary, size: .large))
                } else {
                    Button(legal.callAmount >= (viewModel.human?.stack ?? 0) ? "ALL-IN \(ChipFormat.string(legal.callAmount))"
                                                                             : "CALL \(ChipFormat.string(legal.callAmount))") {
                        Task { await viewModel.act(.call) }
                    }
                    .buttonStyle(.casino(.secondary, size: .large))
                }
                if legal.canRaise {
                    let target = Int(viewModel.raiseTarget)
                    let isAllIn = target >= legal.maxRaiseTo
                    let verb = legal.canCheck ? "BET" : "RAISE"
                    Button(isAllIn ? "ALL-IN \(ChipFormat.string(legal.maxRaiseTo))" : "\(verb) \(ChipFormat.string(target))") {
                        Task { await viewModel.confirmRaise() }
                    }
                    .buttonStyle(.casino(.primary, size: .large))
                }
            }
        }
    }

    private func quickRaise(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.casino(.ghost, size: .small))
    }

    // MARK: - Setup

    private var setupOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TISCH WÄHLEN").font(.display(28)).foregroundStyle(.white)
                        Text("Texas Hold'em gegen KI-Gegner mit eigenen Spielstilen")
                            .font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    ForEach(PokerViewModel.tables) { option in
                        let affordable = model.chips >= option.minBuyIn
                        Button {
                            viewModel.selectedTable = option
                            viewModel.buyIn = viewModel.clampedBuyIn(option.maxBuyIn / 2)
                            Haptics.selection()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(option.name.uppercased()).font(.display(17)).foregroundStyle(.white)
                                Text("Blinds \(option.smallBlind)/\(option.bigBlind)")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.gold)
                                Text("Buy-in \(ChipFormat.compact(option.minBuyIn))–\(ChipFormat.compact(option.maxBuyIn))")
                                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(viewModel.selectedTable == option ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Theme.surfaceRaised)))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(viewModel.selectedTable == option ? Theme.goldLight.opacity(0.6) : Theme.stroke))
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                        .opacity(affordable ? 1 : 0.4)
                    }
                }

                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GEGNER").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textSecondary)
                        Picker("Gegner", selection: $viewModel.opponentCount) {
                            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("BUY-IN").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(ChipFormat.string(viewModel.clampedBuyIn(viewModel.buyIn)))
                                .font(.numeric(20, weight: .black)).foregroundStyle(.white)
                        }
                        let maxBuy = max(viewModel.selectedTable.minBuyIn + 1, min(viewModel.selectedTable.maxBuyIn, model.chips))
                        Slider(value: Binding(get: { Double(viewModel.buyIn) },
                                              set: { viewModel.buyIn = viewModel.clampedBuyIn(Int($0)) }),
                               in: Double(viewModel.selectedTable.minBuyIn)...Double(maxBuy))
                            .tint(Theme.red)
                    }
                }

                HStack {
                    NoCashValueNote(compact: true)
                    Spacer()
                    Button("PLATZ NEHMEN") { Task { await viewModel.sitDown() } }
                        .buttonStyle(.casino(.primary, size: .large))
                        .disabled(!viewModel.canAffordSelectedTable)
                }
                if !viewModel.canAffordSelectedTable {
                    RescueHint()
                }
            }
            .padding(32)
            .frame(maxWidth: 820)
            .glassPanel(cornerRadius: 32)
            .padding(40)
        }
    }
}

/// Info-Plakette eines KI-Gegners.
private struct SeatBadge: View {
    let seat: PokerSeat
    let action: String?
    let isThinking: Bool
    let isButton: Bool
    let revealedHand: String?
    let showCards: Bool

    var body: some View {
        VStack(spacing: 6) {
            if showCards {
                HStack(spacing: -10) {
                    ForEach(Array(seat.holeCards.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: card, width: 44)
                    }
                }
            }
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if isButton {
                        Text("D").font(.system(size: 11, weight: .black)).foregroundStyle(.black)
                            .frame(width: 18, height: 18).background(Circle().fill(.white))
                    }
                    Text(seat.name).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                Text(ChipFormat.string(seat.stack))
                    .font(.numeric(15, weight: .heavy)).foregroundStyle(Theme.goldLight)
                Text(revealedHand ?? action ?? seat.style?.title ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(revealedHand != nil ? Theme.gold : Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.62)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isThinking ? Theme.red.opacity(0.9) : Color.white.opacity(0.10), lineWidth: isThinking ? 1.5 : 1))
            .opacity(seat.hasFolded ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.25), value: isThinking)
        }
        .fixedSize()
    }
}
