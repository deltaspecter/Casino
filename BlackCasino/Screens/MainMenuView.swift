import SwiftUI
import CasinoCore

struct MainMenuView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [Route]
    @Binding var sheet: MenuSheet?

    var body: some View {
        ZStack {
            LightSweepBackground()
            ParticleField(count: 26, speed: 0.5).ignoresSafeArea()

            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        header
                        gameCards(landscape: landscape, height: landscape ? geo.size.height * 0.46 : 300)
                        extras(landscape: landscape)
                        NoCashValueNote()
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: 18) {
            BlackCasinoLogo(size: 30, shimmer: true)
                .fixedSize()
            Spacer()
            ChipBalanceView(amount: model.chips)
            IconButton(systemName: "gearshape.fill") { sheet = .settings }
                .accessibilityLabel("Einstellungen")
        }
    }

    // MARK: - Spiele

    private func gameCards(landscape: Bool, height: CGFloat) -> some View {
        let layout = landscape ? AnyLayout(HStackLayout(spacing: 22)) : AnyLayout(VStackLayout(spacing: 22))
        return layout {
            GameCard(title: "BLACKJACK", subtitle: "Schlag den Dealer bis 21", art: .blackjack) {
                path.append(.blackjack)
            }
            GameCard(title: "POKER", subtitle: "Texas Hold'em gegen KI", art: .poker) {
                path.append(.poker)
            }
            GameCard(title: "SLOTS", subtitle: "3 Automaten · 10 Linien", art: .slots) {
                path.append(.slotsLobby)
            }
        }
        .frame(height: landscape ? height : nil)
        .frame(minHeight: landscape ? 340 : nil)
    }

    // MARK: - Belohnungen

    private func extras(landscape: Bool) -> some View {
        let p = model.profile
        let missionsReady = p.dailyMissions.filter { p.isMissionComplete($0) && !$0.isClaimed }.count
        let missionsClaimed = p.dailyMissions.filter(\.isClaimed).count
        let achievementsReady = p.unlockedAchievements.subtracting(p.claimedAchievements).count

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: landscape ? 200 : 260), spacing: 16)], spacing: 16) {
            ExtraCard(icon: "gift.fill", title: "DAILY REWARD",
                      detail: model.canClaimDailyReward ? "Jetzt abholen" : "Morgen wieder",
                      badge: model.canClaimDailyReward ? "1" : nil) { sheet = .dailyReward }
            ExtraCard(icon: "flag.checkered", title: "MISSIONS",
                      detail: "\(missionsClaimed)/\(p.dailyMissions.count) erledigt",
                      badge: missionsReady > 0 ? "\(missionsReady)" : nil) { sheet = .missions }
            ExtraCard(icon: "trophy.fill", title: "ACHIEVEMENTS",
                      detail: "\(p.unlockedAchievements.count)/\(RewardTable.achievements.count)",
                      badge: achievementsReady > 0 ? "\(achievementsReady)" : nil) { sheet = .achievements }
            ExtraCard(icon: "chart.bar.fill", title: "STATISTICS",
                      detail: "\(ChipFormat.string(p.stats.gamesPlayed)) Runden", badge: nil) { sheet = .statistics }
            ExtraCard(icon: "gearshape.fill", title: "SETTINGS",
                      detail: "Regeln & Fairness", badge: nil) { sheet = .settings }
        }
    }
}

// MARK: - Karten

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct GameCard: View {
    enum Art { case blackjack, poker, slots }

    let title: String
    let subtitle: String
    let art: Art
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.03, blue: 0.05), Theme.surface],
                                         startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [Theme.red.opacity(0.55), .clear], center: .init(x: 0.5, y: 0.35),
                               startRadius: 0, endRadius: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))

                artwork
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 90)
                    .offset(y: hover ? -6 : 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.display(30)).foregroundStyle(.white)
                    HStack {
                        Text(subtitle).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.redGradient)
                    }
                }
                .padding(24)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.gold.opacity(0.55), Theme.red.opacity(0.2), .clear],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
        }
        .buttonStyle(PressableCardStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { hover = true }
        }
        .accessibilityLabel(title)
    }

    @ViewBuilder private var artwork: some View {
        switch art {
        case .blackjack:
            ZStack {
                PlayingCardView(card: Card(.ace, .spades), width: 100)
                    .rotationEffect(.degrees(-12)).offset(x: -34)
                PlayingCardView(card: Card(.king, .hearts), width: 100)
                    .rotationEffect(.degrees(10)).offset(x: 34, y: 6)
            }
        case .poker:
            ZStack {
                ForEach(0..<5) { i in
                    ChipIcon(color: [Theme.red, Color(uiColor: ChipDenomination.hundred.baseColor), Theme.gold][i % 3], size: 64)
                        .offset(x: -50, y: CGFloat(-i * 7) + 30)
                }
                PlayingCardView(card: Card(.queen, .diamonds), width: 86)
                    .rotationEffect(.degrees(-8)).offset(x: 30, y: -6)
                PlayingCardView(card: Card(.queen, .clubs), width: 86)
                    .rotationEffect(.degrees(9)).offset(x: 70, y: 0)
            }
        case .slots:
            HStack(spacing: 8) {
                ForEach(0..<3) { _ in
                    SlotSymbolView(symbolID: "seven", size: 72)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.goldGradient, lineWidth: 2))
        }
    }
}

private struct ExtraCard: View {
    let icon: String
    let title: String
    let detail: String
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.goldGradient)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.gold.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.display(15, weight: .heavy)).tracking(1).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(Circle().fill(Theme.red))
                        .shadow(color: Theme.red.opacity(0.7), radius: 8)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassPanel(cornerRadius: 24)
        }
        .buttonStyle(PressableCardStyle())
    }
}
