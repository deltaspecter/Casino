import SwiftUI

/// Online-Tisch. Zeigt ausschließlich den vom Server gelieferten Zustand (`TableSnapshot`).
/// Buttons senden nur Absichten; das Ergebnis kommt immer vom Server.
struct OnlineTableView: View {
    @Environment(OnlineService.self) private var online
    @Environment(\.dismiss) private var dismiss
    @State private var showRules = false

    var body: some View {
        ZStack {
            FeltBackground()
            if let table = online.table {
                VStack(spacing: 0) {
                    header(table)
                    switch table.game {
                    case .blackjack:
                        if let bj = table.blackjack { OnlineBlackjackTable(table: table, bj: bj) }
                    case .poker:
                        if let poker = table.poker { OnlinePokerTable(table: table, poker: poker) }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView().tint(.white)
                    Text(online.tableClosedReason ?? "Tisch wird geladen …").foregroundStyle(Theme.textSecondary)
                    Button("ZURÜCK") { dismiss() }.buttonStyle(.casino(.secondary, size: .medium))
                }
            }
            ReconnectOverlay {
                online.acknowledgeFailure()
                dismiss()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: online.state)
        .sheet(isPresented: $showRules) { RulesSheet(game: online.table?.game == .blackjack ? .blackjack : .poker) }
        .onChange(of: online.table == nil) { _, closed in
            if closed, online.tableClosedReason != nil { dismiss() }
        }
    }

    private func header(_ table: TableSnapshot) -> some View {
        HStack(spacing: 16) {
            IconButton(systemName: "chevron.left") {
                online.leaveTable()
                dismiss()
            }
            .accessibilityLabel("Tisch verlassen")
            VStack(alignment: .leading, spacing: 2) {
                Text(table.game == .poker ? "ONLINE POKER" : "ONLINE BLACKJACK")
                    .font(.display(20)).tracking(3).foregroundStyle(.white)
                Text(table.isPrivate ? "Privater Raum · Server-autoritativ" : "Öffentlicher Tisch · Server-autoritativ")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            TurnTimer(deadline: table.turnDeadline)
            if let account = online.account { OnlineChipsView(amount: account.onlineChips) }
            Button {
                showRules = true
            } label: {
                Label("RULES", systemImage: "book.closed.fill")
            }
            .buttonStyle(.casino(.secondary, size: .small))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 16)
    }
}

/// Grüner/roter Filz als Hintergrund für 2D-Online-Tische.
private struct FeltBackground: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            GeometryReader { geo in
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.03, blue: 0.06), Color(red: 0.12, green: 0.01, blue: 0.03)],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.55))
                    .overlay(Ellipse().strokeBorder(Color(red: 0.06, green: 0.05, blue: 0.05), lineWidth: 26))
                    .overlay(Ellipse().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 2).padding(13))
                    .frame(width: geo.size.width * 0.94, height: geo.size.height * 0.78)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.52)
                    .shadow(color: Theme.red.opacity(0.25), radius: 60)
            }
            .ignoresSafeArea()
        }
    }
}

/// Restzeit des Spielers am Zug (vom Server vorgegeben).
private struct TurnTimer: View {
    let deadline: Date?

    var body: some View {
        if let deadline {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text("\(remaining) s").font(.numeric(15, weight: .bold))
                }
                .foregroundStyle(remaining <= 5 ? Theme.redBright : Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassPanel(cornerRadius: 18)
            }
        }
    }
}

// MARK: - Blackjack

private struct OnlineBlackjackTable: View {
    @Environment(OnlineService.self) private var online
    let table: TableSnapshot
    let bj: BlackjackTableSnapshot
    @State private var bet = 50

    var body: some View {
        VStack(spacing: 18) {
            // Dealer
            VStack(spacing: 8) {
                Text("DEALER").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textTertiary)
                HStack(spacing: -22) {
                    if bj.dealerCards.isEmpty {
                        Text(bj.bettingOpen ? "Einsätze bitte" : " ").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.goldLight)
                    }
                    ForEach(Array(bj.dealerCards.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: card, faceUp: card != nil, width: 78)
                    }
                }
                .frame(height: 112)
                if let value = bj.dealerVisibleValue {
                    FloatingTag(text: value.display, detail: bj.dealerCards.contains(nil) ? "offene Karte" : "Dealer")
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            // Plätze
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(bj.seats) { seat in
                    SeatColumn(table: table, bj: bj, seat: seat)
                }
            }
            .padding(.horizontal, Theme.gutter)

            controls
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder private var controls: some View {
        let mySeat = table.yourSeatID.flatMap { id in bj.seats.first { $0.seatID == id } }
        HStack(spacing: 14) {
            if bj.bettingOpen {
                if let pending = mySeat?.pendingBet {
                    Label("Einsatz \(ChipFormat.string(pending)) gesetzt – warte auf andere Spieler", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                } else {
                    Stepper(value: $bet, in: bj.minBet...bj.maxBet, step: 10) {
                        Text("Einsatz \(ChipFormat.string(bet))").font(.numeric(20, weight: .heavy)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: 320)
                    Button("SETZEN") { online.act(.placeBet(amount: bet)) }
                        .buttonStyle(.casino(.primary, size: .large))
                        .disabled(!online.canAct)
                }
            } else if !bj.yourActions.isEmpty {
                ForEach([BlackjackAction.hit, .stand, .double, .split], id: \.self) { action in
                    Button(action.rawValue.uppercased()) { online.act(.blackjack(action: action)) }
                        .buttonStyle(.casino(action == .hit ? .primary : action == .double ? .gold : .secondary, size: .large, fullWidth: true))
                        .disabled(!online.canAct || !bj.yourActions.contains(action))
                }
            } else if bj.phase == .settled {
                Text("Runde abgerechnet – nächste Runde startet gleich").foregroundStyle(Theme.textSecondary)
            } else if let current = bj.currentSeatID, let name = table.seat(current)?.player.displayName {
                Text("\(name) ist am Zug …").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 28)
    }
}

private struct SeatColumn: View {
    let table: TableSnapshot
    let bj: BlackjackTableSnapshot
    let seat: BlackjackSeatSnapshot

    var body: some View {
        let info = table.seat(seat.seatID)
        let isMe = seat.seatID == table.yourSeatID
        VStack(spacing: 8) {
            ForEach(seat.hands) { hand in
                VStack(spacing: 6) {
                    HStack(spacing: -40) {
                        ForEach(Array(hand.cards.enumerated()), id: \.offset) { _, card in
                            PlayingCardView(card: card, width: 62)
                        }
                    }
                    FloatingTag(text: hand.result?.outcome.title ?? hand.value.display,
                                detail: "Einsatz \(ChipFormat.string(hand.bet))",
                                highlighted: bj.currentHandID == hand.id && bj.currentSeatID == seat.seatID
                                    || hand.result?.outcome == .win || hand.result?.outcome == .blackjack)
                }
            }
            if let pending = seat.pendingBet {
                HStack(spacing: 6) { ChipIcon(size: 18); Text(ChipFormat.string(pending)).font(.numeric(14, weight: .bold)) }
                    .foregroundStyle(.white)
            }
            NameplateView(seat: info, isMe: isMe, isTurn: bj.currentSeatID == seat.seatID)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NameplateView: View {
    let seat: TableSeat?
    let isMe: Bool
    let isTurn: Bool

    var body: some View {
        HStack(spacing: 6) {
            if seat?.isBot == true {
                Text("BOT").font(.system(size: 10, weight: .black)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.gold.opacity(0.25))).foregroundStyle(Theme.goldLight)
            }
            Text(isMe ? "Du" : (seat?.player.displayName ?? "–")).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            if seat?.isConnected == false {
                Image(systemName: "wifi.slash").font(.system(size: 11)).foregroundStyle(Theme.redBright)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(isTurn ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Color.black.opacity(0.6))))
        .overlay(Capsule().strokeBorder(isMe ? Theme.goldLight.opacity(0.7) : Color.white.opacity(0.12)))
    }
}

// MARK: - Poker

private struct OnlinePokerTable: View {
    @Environment(OnlineService.self) private var online
    let table: TableSnapshot
    let poker: PokerTableSnapshot
    @State private var raiseTarget: Double = 0

    private var me: PokerPlayerSnapshot? { table.yourSeatID.flatMap { poker.player($0) } }
    private var others: [PokerPlayerSnapshot] { poker.players.filter { $0.seatID != table.yourSeatID } }

    var body: some View {
        VStack(spacing: 14) {
            // Gegner
            HStack(alignment: .top, spacing: 14) {
                ForEach(others) { player in
                    OpponentView(player: player, seat: table.seat(player.seatID), poker: poker)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)

            Spacer(minLength: 0)

            // Board und Pot – für alle Spieler identisch
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { i in
                        if i < poker.community.count {
                            PlayingCardView(card: poker.community[i], width: 74)
                        } else {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                .frame(width: 74, height: 104)
                        }
                    }
                }
                HStack(spacing: 14) {
                    FloatingTag(text: ChipFormat.string(poker.pot), detail: "POT")
                    Text(poker.street.title.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(2).foregroundStyle(Theme.gold)
                    Text("Blinds \(poker.smallBlind)/\(poker.bigBlind)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(poker.awards.enumerated()), id: \.offset) { _, award in
                    let name = award.seatID == table.yourSeatID ? "Du gewinnst" : "\(table.seat(award.seatID)?.player.displayName ?? "?") gewinnt"
                    Text("\(name) \(ChipFormat.string(award.amount))\(award.handName.map { " mit \($0)" } ?? "")")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(award.seatID == table.yourSeatID ? Theme.goldLight : .white)
                }
            }

            Spacer(minLength: 0)

            bottom
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
        }
        .onChange(of: poker.yourLegalActions) { _, legal in
            if let legal { raiseTarget = Double(legal.minRaiseTo) }
        }
    }

    private var bottom: some View {
        HStack(alignment: .bottom, spacing: 18) {
            // Eigene Karten
            HStack(spacing: 12) {
                HStack(spacing: -16) {
                    ForEach(Array((me?.holeCards ?? []).enumerated()), id: \.offset) { i, card in
                        PlayingCardView(card: card, width: 84)
                            .rotationEffect(.degrees(i == 0 ? -6 : 6), anchor: .bottom)
                    }
                }
                .frame(minWidth: 150, minHeight: 124)
                .opacity(me?.hasFolded == true ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dein Stack").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    Text(ChipFormat.string(me?.stack ?? 0)).font(.numeric(24, weight: .black)).foregroundStyle(.white)
                    if let cards = me?.holeCards, poker.community.count >= 3, me?.hasFolded == false {
                        Text(HandEvaluator.bestHand(cards + poker.community).name.uppercased())
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.gold)
                    }
                    if poker.buttonSeatID == table.yourSeatID {
                        Text("DEALER-BUTTON").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(14)
            .glassPanel(cornerRadius: 24, tint: poker.yourLegalActions != nil ? Theme.redDeep : .black)

            Spacer(minLength: 0)
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        if let legal = poker.yourLegalActions {
            VStack(alignment: .trailing, spacing: 10) {
                if legal.canRaise && legal.maxRaiseTo > legal.minRaiseTo {
                    HStack {
                        Text("\(legal.canCheck ? "Bet" : "Raise") auf \(ChipFormat.string(Int(raiseTarget)))")
                            .font(.numeric(14, weight: .bold)).foregroundStyle(.white)
                        Slider(value: $raiseTarget, in: Double(legal.minRaiseTo)...Double(legal.maxRaiseTo),
                               step: Double(max(1, min(poker.bigBlind, legal.maxRaiseTo - legal.minRaiseTo))))
                            .tint(Theme.red)
                            .frame(width: 220)
                    }
                    .padding(10)
                    .glassPanel(cornerRadius: 18)
                }
                HStack(spacing: 12) {
                    Button("FOLD") { online.act(.poker(action: .fold)) }
                        .buttonStyle(.casino(.secondary, size: .large))
                    if legal.canCheck {
                        Button("CHECK") { online.act(.poker(action: .check)) }
                            .buttonStyle(.casino(.secondary, size: .large))
                    } else {
                        Button("CALL \(ChipFormat.string(legal.callAmount))") { online.act(.poker(action: .call)) }
                            .buttonStyle(.casino(.secondary, size: .large))
                    }
                    if legal.canRaise {
                        let target = max(Int(raiseTarget), legal.minRaiseTo)
                        Button(target >= legal.maxRaiseTo ? "ALL-IN" : "\(legal.canCheck ? "BET" : "RAISE") \(ChipFormat.string(target))") {
                            online.act(.poker(action: target >= legal.maxRaiseTo ? .allIn : .raise(to: target)))
                        }
                        .buttonStyle(.casino(.primary, size: .large))
                    }
                }
                .disabled(!online.canAct)
            }
        } else if me?.stack == 0 && poker.isHandInProgress == false {
            Button("NACHKAUFEN") { online.act(.rebuy) }
                .buttonStyle(.casino(.gold, size: .large))
                .disabled(!online.canAct)
        } else {
            Text(statusText)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 20).padding(.horizontal, 24)
                .glassPanel(cornerRadius: 22)
        }
    }

    private var statusText: String {
        if !poker.isHandInProgress { return poker.players.filter { $0.stack > 0 }.count < 2 ? "Warte auf weitere Spieler …" : "Nächste Hand startet gleich …" }
        if let current = poker.currentSeatID, let name = table.seat(current)?.player.displayName { return "\(name) ist am Zug …" }
        return " "
    }
}

private struct OpponentView: View {
    let player: PokerPlayerSnapshot
    let seat: TableSeat?
    let poker: PokerTableSnapshot

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: -12) {
                if let cards = player.holeCards {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in PlayingCardView(card: card, width: 44) }
                } else if player.hasCards {
                    PlayingCardView(card: nil, faceUp: false, width: 44)
                    PlayingCardView(card: nil, faceUp: false, width: 44)
                }
            }
            .frame(height: 64)
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    if poker.buttonSeatID == player.seatID {
                        Text("D").font(.system(size: 10, weight: .black)).foregroundStyle(.black)
                            .frame(width: 16, height: 16).background(Circle().fill(.white))
                    }
                    if seat?.isBot == true {
                        Text("BOT").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.goldLight)
                    }
                    Text(seat?.player.displayName ?? "–").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    if seat?.isConnected == false { Image(systemName: "wifi.slash").font(.system(size: 10)).foregroundStyle(Theme.redBright) }
                }
                Text(ChipFormat.string(player.stack)).font(.numeric(14, weight: .heavy)).foregroundStyle(Theme.goldLight)
                Text(detail).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(poker.currentSeatID == player.seatID ? AnyShapeStyle(Theme.redGradient) : AnyShapeStyle(Color.black.opacity(0.6))))
            .opacity(player.hasFolded || player.isSittingOut ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var detail: String {
        if let show = poker.showdown.first(where: { $0.seatID == player.seatID }) { return show.handName }
        if player.isSittingOut { return "setzt aus" }
        if let action = player.lastAction {
            return action.kind == .fold || action.kind == .check ? action.kind.title : "\(action.kind.title) \(ChipFormat.compact(action.streetTotal))"
        }
        return seat?.botStyle ?? ""
    }
}
