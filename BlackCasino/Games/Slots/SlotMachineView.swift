import SwiftUI
import CasinoCore

struct SlotMachineView: View {
    @Environment(AppModel.self) private var model
    let machineID: String
    @State private var viewModel: SlotsViewModel?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let viewModel {
                SlotMachineScreen(viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = SlotsViewModel(machineID: machineID, app: model) }
        }
    }
}

private struct SlotMachineScreen: View {
    @Environment(AppModel.self) private var model
    let viewModel: SlotsViewModel
    @State private var showPaytable = false
    @State private var showTutorial = false

    var body: some View {
        let theme = viewModel.theme
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            RadialGradient(colors: [theme.glow.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()
            ParticleField(count: 30, colors: [theme.accent, theme.glow, Theme.gold], speed: 0.7)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                GameTopBar(title: viewModel.definition.name.uppercased(),
                           subtitle: viewModel.definition.tagline,
                           balance: model.chips - viewModel.pendingWin,
                           onLeave: { viewModel.stopEffects() },
                           onRules: { showPaytable = true },
                           onHelp: { showTutorial = true })

                GeometryReader { geo in
                    let cell = min((geo.size.width - 140) / 5, (geo.size.height - 40) / 3, 170)
                    cabinet(cell: cell)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                controlBar
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 22)
            }

            if let celebration = viewModel.celebration {
                // Dezente Gewinnanzeige statt Vollbild-Effekt
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ParticleField(count: 18, colors: [Theme.gold, Theme.goldLight], speed: 0.8)
                        .frame(width: 520, height: 260)
                    WinCelebration(title: celebration.title, amount: celebration.amount)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.celebration)
        .onAppear {
            if !model.isTutorialCompleted(.slots) { showTutorial = true }
        }
        .onDisappear { viewModel.stopEffects() }
        .sheet(isPresented: $showPaytable) { PaytableSheet(definition: viewModel.definition) }
        .sheet(isPresented: $showTutorial) { TutorialSheet(game: .slots) }
    }

    // MARK: - Automat

    private func cabinet(cell: CGFloat) -> some View {
        let theme = viewModel.theme
        let spacing: CGFloat = 10
        let gridWidth = cell * 5 + spacing * 4
        let gridHeight = cell * 3

        return ZStack {
            HStack(spacing: spacing) {
                ForEach(Array(viewModel.reels.enumerated()), id: \.offset) { index, reel in
                    ReelView(reel: reel, reelIndex: index, cell: cell, highlighted: viewModel.highlighted)
                }
            }
            .frame(width: gridWidth, height: gridHeight)

            if let line = viewModel.activeLine {
                PaylinePath(line: viewModel.definition.paylines[line.lineIndex], cell: cell, spacing: spacing,
                            count: line.count)
                    .stroke(theme.paylineColors[line.lineIndex % theme.paylineColors.count],
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .shadow(color: theme.paylineColors[line.lineIndex % theme.paylineColors.count], radius: 8)
                    .frame(width: gridWidth, height: gridHeight)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.08), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(LinearGradient(colors: [theme.glow, theme.accent.opacity(0.4), theme.glow],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
        )
        .shadow(color: theme.glow.opacity(0.45), radius: 30)
        .padding(.vertical, 14)
    }

    // MARK: - Bedienung

    private var controlBar: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EINSATZ").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 12) {
                    stepButton("minus") { viewModel.changeBet(by: -1) }
                    VStack(spacing: 0) {
                        Text(ChipFormat.string(viewModel.totalBet))
                            .font(.numeric(26, weight: .black)).foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(viewModel.totalBet)))
                        Text("\(viewModel.definition.paylines.count) Linien × \(viewModel.lineBet)")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(minWidth: 110)
                    stepButton("plus") { viewModel.changeBet(by: 1) }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("GEWINN").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textSecondary)
                Text(ChipFormat.string(viewModel.displayedWin))
                    .font(.numeric(30, weight: .black))
                    .foregroundStyle(viewModel.displayedWin > 0 ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.white.opacity(0.4)))
                    .contentTransition(.numericText(value: Double(viewModel.displayedWin)))
            }
            .frame(minWidth: 150, alignment: .trailing)

            Button {
                Task { await viewModel.spin() }
            } label: {
                ZStack {
                    Circle().fill(Theme.redGradient)
                    Circle().strokeBorder(Theme.goldLight.opacity(0.7), lineWidth: 3)
                    Image(systemName: viewModel.isSpinning ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(viewModel.isSpinning ? 180 : 0))
                }
                .frame(width: 104, height: 104)
                .shadow(color: Theme.red.opacity(0.7), radius: viewModel.isSpinning ? 8 : 22)
            }
            .buttonStyle(SpinButtonStyle())
            .disabled(viewModel.isSpinning || model.chips < viewModel.totalBet)
            .accessibilityLabel("Drehen")
        }
        .padding(18)
        .glassPanel(cornerRadius: 34)
        .overlay(alignment: .top) {
            if model.chips < viewModel.totalBet && !viewModel.isSpinning {
                RescueHint().offset(y: -70)
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .black))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.surfaceRaised))
                .overlay(Circle().strokeBorder(Theme.stroke))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSpinning)
    }
}

private struct SpinButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Eine Walze: lange Symbolspalte, die hinter einem Fenster vorbeiläuft.
private struct ReelView: View {
    let reel: SlotsViewModel.ReelColumn
    let reelIndex: Int
    let cell: CGFloat
    let highlighted: Set<SlotPosition>

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(reel.symbols.enumerated()), id: \.offset) { index, symbol in
                // Index 1…3 ist im Ruhezustand sichtbar (0 und 4 sind Puffer)
                let row = index - 1
                SlotSymbolView(symbolID: symbol, size: cell * 0.92,
                               highlighted: !reel.isSpinning && reel.symbols.count == 5 && highlighted.contains(SlotPosition(reel: reelIndex, row: row)))
                    .frame(width: cell, height: cell)
            }
        }
        .offset(y: -reel.offset * cell)
        .blur(radius: reel.isSpinning ? 1.6 : 0)
        .frame(width: cell, height: cell * 3, alignment: .top)
        .clipped()
        .background(
            LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.015), Color.white.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            // Wölbung der Walze andeuten
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Verbindungslinie einer Gewinnlinie über die getroffenen Walzen.
private struct PaylinePath: Shape {
    let line: [Int]
    let cell: CGFloat
    let spacing: CGFloat
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (reel, row) in line.enumerated() {
            let point = CGPoint(x: CGFloat(reel) * (cell + spacing) + cell / 2, y: CGFloat(row) * cell + cell / 2)
            if reel == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Mini-Darstellung einer Gewinnlinie im 5×3-Raster.
private struct PaylineDiagram: View {
    let line: [Int]
    let rows: Int

    var body: some View {
        Canvas { context, size in
            let cw = size.width / CGFloat(line.count), ch = size.height / CGFloat(rows)
            for c in 0..<line.count {
                for r in 0..<rows {
                    let rect = CGRect(x: CGFloat(c) * cw + 1, y: CGFloat(r) * ch + 1, width: cw - 2, height: ch - 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3),
                                 with: .color(line[c] == r ? Theme.red : Color.white.opacity(0.08)))
                }
            }
        }
    }
}

/// Regelwerk des Automaten: Auszahlungstabelle, Regeln, Gewinnlinien, Wahrscheinlichkeiten und RTP.
struct PaytableSheet: View {
    @Environment(\.dismiss) private var dismiss
    let definition: SlotMachineDefinition

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("RULES · \(definition.name.uppercased())").font(.display(26)).foregroundStyle(.white)
                    Spacer()
                    IconButton(systemName: "xmark", size: 40) { dismiss() }
                }

                SectionTitle(title: "Auszahlungen", subtitle: "Vielfaches des Linieneinsatzes · Scatter: Vielfaches des Gesamteinsatzes")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(definition.symbols.reversed()) { symbol in
                        HStack(spacing: 14) {
                            SlotSymbolView(symbolID: symbol.id, size: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach([5, 4, 3], id: \.self) { n in
                                    HStack {
                                        Text("\(n)×").foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text("\(symbol.payout(for: n))").foregroundStyle(.white)
                                    }
                                    .font(.numeric(15, weight: .bold))
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surfaceRaised))
                    }
                }

                SectionTitle(title: "Regeln")
                VStack(alignment: .leading, spacing: 10) {
                    rule("\(definition.reelCount) Walzen × \(definition.rows) Reihen, \(definition.paylines.count) feste Gewinnlinien (alle immer aktiv).")
                    rule("Gesamteinsatz = Linieneinsatz × \(definition.paylines.count). Linieneinsätze: \(definition.lineBetOptions.map(String.init).joined(separator: ", ")).")
                    rule("Liniengewinne zählen von links nach rechts ab Walze 1, ab 3 gleichen Symbolen. Pro Linie wird nur der höchste Gewinn gezahlt.")
                    rule("WILD ersetzt alle normalen Symbole, aber keinen SCATTER. Drei oder mehr WILD am Linienanfang zahlen selbst.")
                    rule("SCATTER zahlt an jeder Position (Anzahl × Tabelle × Gesamteinsatz). Linien- und Scatter-Gewinne werden addiert.")
                    rule("Es gibt keine Bonus-Symbole, Freispiele oder Jackpots.")
                }

                SectionTitle(title: "Gewinnlinien")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(Array(definition.paylines.enumerated()), id: \.offset) { index, line in
                        VStack(spacing: 6) {
                            PaylineDiagram(line: line, rows: definition.rows)
                                .frame(width: 100, height: 60)
                            Text("Linie \(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceRaised))
                    }
                }

                SectionTitle(title: "Zufall & Wahrscheinlichkeiten",
                             subtitle: "Jede Walze stoppt an einer gleichverteilt gezogenen Position ihres festen Streifens. Wahrscheinlichkeit eines Symbols an einer Position = Anzahl auf dem Streifen ÷ Streifenlänge.")
                VStack(spacing: 0) {
                    HStack {
                        Text("Symbol").frame(width: 90, alignment: .leading)
                        ForEach(0..<definition.reelCount, id: \.self) { reel in
                            Text("Walze \(reel + 1)").frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
                    ForEach(definition.symbols) { symbol in
                        HStack {
                            SlotSymbolView(symbolID: symbol.id, size: 36).frame(width: 90, alignment: .leading)
                            ForEach(0..<definition.reelCount, id: \.self) { reel in
                                VStack(spacing: 0) {
                                    Text("\(definition.count(of: symbol.id, onReel: reel))/\(definition.reelStrips[reel].count)")
                                        .font(.numeric(13, weight: .bold)).foregroundStyle(.white)
                                    Text(String(format: "%.1f %%", definition.probability(of: symbol.id, onReel: reel) * 100))
                                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider().overlay(Theme.stroke)
                    }
                }
                .padding(14)
                .glassPanel(cornerRadius: 18)

                SectionTitle(title: "Transparenz")
                HStack(spacing: 16) {
                    Image(systemName: "function").font(.system(size: 28)).foregroundStyle(Theme.gold)
                    Text("Theoretische Auszahlungsquote: **\(SlotInfo.rtpText(definition.id))** – exakt berechnet aus Walzenstreifen und Gewinntabelle. Es gibt keine Steuerung von Gewinnen oder Verlusten.")
                        .foregroundStyle(Theme.textSecondary)
                }
                NoCashValueNote()
            }
            .padding(32)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(32)
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.red).frame(width: 7, height: 7).padding(.top, 7)
            Text(text).foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 16))
    }
}
