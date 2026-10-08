import SwiftUI
import CasinoCore
import CasinoNet

/// Online-Tisch. Zeigt ausschließlich den vom Server gelieferten Zustand (`TableSnapshot`).
/// Buttons senden nur Absichten; das Ergebnis kommt immer vom Server.
struct OnlineTableView: View {
    @Environment(OnlineService.self) private var online
    @Environment(\.dismiss) private var dismiss
    @State private var showRules = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let table = online.table {
                switch table.game {
                case .blackjack:
                    if let bj = table.blackjack {
                        OnlineBlackjackTable(table: table, bj: bj, header: header(table))
                    }
                case .poker:
                    if let poker = table.poker {
                        OnlinePokerTable(table: table, poker: poker, header: header(table))
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
            Button {
                showRules = true
            } label: {
                Label("RULES", systemImage: "book.closed.fill")
            }
            .buttonStyle(.casino(.secondary, size: .small))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
    }
}

/// Tischfläche mit leichter Perspektive – wie der Blick vom eigenen Platz auf einen echten Tisch.
private struct TableSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            FeltSurface()
            content()
                .padding(.horizontal, 60)
                .padding(.vertical, 34)
        }
        .rotation3DEffect(.degrees(10), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.35)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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

private struct Nameplate: View {
    let seat: TableSeat?
    let isMe: Bool
    let isTurn: Bool
    var detail: String?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                if seat?.isBot == true {
                    Text("BOT").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.goldLight)
                }
                Text(isMe ? "Du" : (seat?.player.displayName ?? "–"))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                if seat?.isConnected == false {
                    Image(systemName: "wifi.slash").font(.system(size: 10)).foregroundStyle(Theme.redBright)
                }
            }
            if let detail {
                Text(detail).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isTurn ? Theme.red : (isMe ? Theme.gold.opacity(0.5) : Color.white.opacity(0.1)), lineWidth: isTurn ? 1.5 : 1))
    }
}

/// Überlappender Kartenfächer mit Austeil-Animation.
private struct CardFan: View {
    let cards: [Card]
    var width: CGFloat = 70
    var overlap: CGFloat = 0.55

    var body: some View {
        HStack(spacing: -width * overlap) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                PlayingCardView(card: card, width: width)
                    .rotationEffect(.degrees(Double(index - cards.count / 2) * 2.5), anchor: .bottom)
                    .transition(.cardDeal)
            }
        }
        .animation(.cardDeal, value: cards.map(\.id))
    }
}

// MARK: - Blackjack

private struct OnlineBlackjackTable<Header: View>: View {
    @Environment(OnlineService.self) private var online
    let table: TableSnapshot
    let bj: BlackjackTableSnapshot
    let header: Header
    @State private var bet = 50

    private var mySeat: BlackjackSeatSnapshot? { table.yourSeatID.flatMap { id in bj.seats.first { $0.seatID == id } } }

    var body: some View {
        VStack(spacing: 0) {
            header
            TableSurface {
                VStack(spacing: 0) {
                    // Dealer: verdeckte Karte dreht sich beim Aufdecken um
                    HStack(spacing: -40) {
                        ForEach(Array(bj.dealerCards.enumerated()), id: \.offset) { _, card in
                            FlippableCardView(card: card, width: 80)
                                .transition(.cardDeal)
                        }
                    }
                    .frame(height: 118)
                    .animation(.cardDeal, value: bj.dealerCards.count)
                    Text(bj.bettingOpen ? "BITTE EINSÄTZE PLATZIEREN" : "DEALER STEHT AUF ALLEN 17")
                        .font(.system(size: 11, weight: .bold)).tracking(3)
                        .foregroundStyle(Color(red: 0.93, green: 0.87, blue: 0.70).opacity(0.55))
                        .padding(.top, 8)
                    Spacer(minLength: 12)
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(bj.seats) { seat in seatView(seat) }
                    }
                }
            }
            TableBar { info } controls: { controls }
        }
    }

    private func seatView(_ seat: BlackjackSeatSnapshot) -> some View {
        let isMe = seat.seatID == table.yourSeatID
        let stake = seat.hands.isEmpty ? (seat.pendingBet ?? 0) : seat.hands.reduce(0) { $0 + $1.bet }
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(seat.hands) { hand in
                    CardFan(cards: hand.cards, width: isMe ? 68 : 56)
                        .overlay(alignment: .top) {
                            if bj.currentHandID == hand.id && bj.currentSeatID == seat.seatID {
                                Capsule().fill(Theme.red).frame(width: 30, height: 4).offset(y: -10)
                            }
                        }
                }
            }
            .frame(minHeight: isMe ? 96 : 80)
            ChipStackView(amount: stake, chipWidth: 34, maxChips: 8)
                .opacity(stake > 0 ? 1 : 0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stake)
            Nameplate(seat: table.seat(seat.seatID), isMe: isMe, isTurn: bj.currentSeatID == seat.seatID,
                      detail: seat.hands.count == 1 ? (seat.hands[0].result?.outcome.title ?? seat.hands[0].value.display) : nil)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var info: some View {
        if let account = online.account {
            InfoItem(title: "Online-Chips", value: ChipFormat.string(account.onlineChips))
        }
        InfoItem(title: "Einsatz", value: ChipFormat.string(mySeat.map { $0.hands.isEmpty ? ($0.pendingBet ?? 0) : $0.hands.reduce(0) { $0 + $1.bet } } ?? 0))
        if let dealer = bj.dealerVisibleValue {
            InfoItem(title: "Dealer", value: dealer.display)
        }
        if let hands = mySeat?.hands, !hands.isEmpty {
            InfoItem(title: "Deine Hand",
                     value: hands.map { $0.result?.outcome.title ?? $0.value.display }.joined(separator: " · "),
                     highlighted: bj.currentSeatID == table.yourSeatID)
        }
        Spacer(minLength: 0)
        if let hands = mySeat?.hands, bj.phase == .settled, hands.allSatisfy({ $0.result != nil }), !hands.isEmpty {
            let net = hands.compactMap(\.result).reduce(0) { $0 + $1.net }
            ResultPill(title: net > 0 ? "GEWONNEN" : net < 0 ? "VERLOREN" : "PUSH", net: net)
        } else if let current = bj.currentSeatID, current != table.yourSeatID, let name = table.seat(current)?.player.displayName {
            Text("\(name) ist am Zug …").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var controls: some View {
        if bj.bettingOpen {
            if let pending = mySeat?.pendingBet {
                Label("Einsatz \(ChipFormat.string(pending)) gesetzt – warte auf andere Spieler", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .frame(maxWidth: .infinity, minHeight: 68)
            } else {
                HStack(spacing: 18) {
                    ChipStackView(amount: bet, chipWidth: 40, maxChips: 8)
                    Stepper(value: $bet, in: bj.minBet...bj.maxBet, step: 10) {
                        Text("Einsatz \(ChipFormat.string(bet))").font(.numeric(20, weight: .heavy)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: 320)
                    Spacer(minLength: 0)
                    Button("SETZEN") {
                        Haptics.chip()
                        online.act(.placeBet(amount: bet))
                    }
                    .buttonStyle(.casino(.primary, size: .large))
                    .disabled(!online.canAct)
                }
            }
        } else if !bj.yourActions.isEmpty {
            HStack(spacing: 12) {
                ForEach([BlackjackAction.hit, .stand, .double, .split], id: \.self) { action in
                    Button(action.rawValue.uppercased()) {
                        Haptics.tap()
                        online.act(.blackjack(action: action))
                    }
                    .buttonStyle(.casino(action == .hit ? .primary : action == .double ? .gold : .secondary, size: .large, fullWidth: true))
                    .disabled(!online.canAct || !bj.yourActions.contains(action))
                }
            }
        } else {
            Text(bj.phase == .settled ? "Nächste Runde startet gleich …" : "Warte auf den Server …")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 68)
        }
    }
}

// MARK: - Poker

private struct OnlinePokerTable<Header: View>: View {
    @Environment(OnlineService.self) private var online
    let table: TableSnapshot
    let poker: PokerTableSnapshot
    let header: Header
    @State private var raiseTarget: Double = 0

    private var me: PokerPlayerSnapshot? { table.yourSeatID.flatMap { poker.player($0) } }
    private var others: [PokerPlayerSnapshot] { poker.players.filter { $0.seatID != table.yourSeatID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            TableSurface {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(others) { player in opponent(player) }
                    }
                    Spacer(minLength: 8)
                    board
                    Spacer(minLength: 8)
                    myArea
                }
            }
            TableBar { info } controls: { HStack { Spacer(minLength: 0); actions } }
        }
        .onChange(of: poker.yourLegalActions) { _, legal in
            if let legal { raiseTarget = Double(legal.minRaiseTo) }
        }
    }

    private var board: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1.2)
                            .frame(width: 72, height: 101)
                        if i < poker.community.count {
                            PlayingCardView(card: poker.community[i], width: 72)
                                .transition(.cardDeal)
                        }
                    }
                }
            }
            .animation(.cardDeal, value: poker.community.count)
            if poker.pot > 0 {
                HStack(spacing: 8) {
                    ChipStackView(amount: poker.pot, chipWidth: 34, maxChips: 12)
                    Text("Pot \(ChipFormat.string(poker.pot))")
                        .font(.numeric(13, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                }
                .transition(.opacity)
            }
        }
    }

    private var myArea: some View {
        HStack(alignment: .bottom, spacing: 16) {
            if let bet = me?.streetBet, bet > 0 {
                ChipStackView(amount: bet, chipWidth: 34, maxChips: 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CardFan(cards: me?.holeCards ?? [], width: 82, overlap: 0.3)
                .opacity(me?.hasFolded == true ? 0.45 : 1)
            Nameplate(seat: table.yourSeatID.flatMap { table.seat($0) }, isMe: true,
                      isTurn: poker.currentSeatID == table.yourSeatID,
                      detail: poker.buttonSeatID == table.yourSeatID ? "Dealer-Button" : nil)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: me?.streetBet)
    }

    private func opponent(_ player: PokerPlayerSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: -22) {
                if let cards = player.holeCards {
                    ForEach(cards) { card in PlayingCardView(card: card, width: 46).transition(.cardDeal) }
                } else if player.hasCards {
                    PlayingCardView(card: nil, faceUp: false, width: 46).transition(.cardDeal)
                    PlayingCardView(card: nil, faceUp: false, width: 46).transition(.cardDeal)
                }
            }
            .frame(height: 66)
            .animation(.cardDeal, value: player.hasCards)
            Nameplate(seat: table.seat(player.seatID), isMe: false, isTurn: poker.currentSeatID == player.seatID,
                      detail: detail(for: player))
            if player.streetBet > 0 {
                ChipStackView(amount: player.streetBet, chipWidth: 28, maxChips: 6)
                    .transition(.opacity)
            }
        }
        .opacity(player.hasFolded || player.isSittingOut ? 0.5 : 1)
        .frame(maxWidth: .infinity)
    }

    private func detail(for player: PokerPlayerSnapshot) -> String {
        if let show = poker.showdown.first(where: { $0.seatID == player.seatID }) { return show.handName }
        if player.isSittingOut { return "setzt aus" }
        var parts = [ChipFormat.string(player.stack)]
        if poker.buttonSeatID == player.seatID { parts.append("D") }
        if let action = player.lastAction { parts.append(action.kind.title) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var info: some View {
        if let account = online.account {
            InfoItem(title: "Online-Chips", value: ChipFormat.string(account.onlineChips))
        }
        InfoItem(title: "Dein Stack", value: ChipFormat.string(me?.stack ?? 0))
        InfoItem(title: "Einsatz", value: ChipFormat.string(me?.streetBet ?? 0))
        InfoItem(title: "Pot", value: ChipFormat.string(poker.pot))
        if let cards = me?.holeCards, poker.community.count >= 3, me?.hasFolded == false {
            InfoItem(title: "Deine Hand", value: HandEvaluator.bestHand(cards + poker.community).name, valueColor: Theme.goldLight)
        }
        Spacer(minLength: 0)
        if let award = poker.awards.first {
            let name = award.seatID == table.yourSeatID ? "Du gewinnst" : "\(table.seat(award.seatID)?.player.displayName ?? "?") gewinnt"
            Text("\(name) \(ChipFormat.string(award.amount))\(award.handName.map { " · \($0)" } ?? "")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(award.seatID == table.yourSeatID ? Theme.goldLight : Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var actions: some View {
        if let legal = poker.yourLegalActions {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { raiseRow(legal); buttons(legal) }
                VStack(alignment: .trailing, spacing: 10) { raiseRow(legal); buttons(legal) }
            }
        } else if me?.stack == 0 && !poker.isHandInProgress {
            Button("NACHKAUFEN") { online.act(.rebuy) }
                .buttonStyle(.casino(.gold, size: .large))
                .disabled(!online.canAct)
        } else {
            Text(statusText)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 68)
        }
    }

    @ViewBuilder private func raiseRow(_ legal: PokerLegalActions) -> some View {
        if legal.canRaise && legal.maxRaiseTo > legal.minRaiseTo {
            Slider(value: $raiseTarget, in: Double(legal.minRaiseTo)...Double(legal.maxRaiseTo),
                   step: Double(max(1, min(poker.bigBlind, legal.maxRaiseTo - legal.minRaiseTo))))
                .tint(Theme.red)
                .frame(minWidth: 180, maxWidth: 260)
        }
    }

    private func buttons(_ legal: PokerLegalActions) -> some View {
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
                    Haptics.chip()
                    online.act(.poker(action: target >= legal.maxRaiseTo ? .allIn : .raise(to: target)))
                }
                .buttonStyle(.casino(.primary, size: .large))
            }
        }
        .disabled(!online.canAct)
    }

    private var statusText: String {
        if !poker.isHandInProgress { return poker.players.filter { $0.stack > 0 }.count < 2 ? "Warte auf weitere Spieler …" : "Nächste Hand startet gleich …" }
        if let current = poker.currentSeatID, let name = table.seat(current)?.player.displayName { return "\(name) ist am Zug …" }
        return " "
    }
}
