import SwiftUI
import CasinoCore

enum Route: Hashable {
    case blackjack
    case poker
    case slotsLobby
    case slotMachine(id: String)
}

enum MenuSheet: String, Identifiable {
    case dailyReward, missions, achievements, statistics, settings
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            switch model.phase {
            case .loading:
                LoadingView()
                    .transition(.opacity)
            case .start:
                StartView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .lobby:
                LobbyContainer()
                    .transition(.opacity)
            }

            ToastStack(toasts: model.toasts)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.8), value: model.phase)
    }
}

/// Navigation des Hauptbereichs. Spiele laufen im Vollbild ohne System-Navigationsleiste.
struct LobbyContainer: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var sheet: MenuSheet?

    var body: some View {
        NavigationStack(path: $path) {
            MainMenuView(path: $path, sheet: $sheet)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .blackjack: BlackjackView()
                        case .poker: PokerView()
                        case .slotsLobby: SlotsLobbyView(path: $path)
                        case .slotMachine(let id): SlotMachineView(machineID: id)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .dailyReward: DailyRewardView()
                case .missions: MissionsView()
                case .achievements: AchievementsView()
                case .statistics: StatisticsView()
                case .settings: SettingsView()
                }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(32)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: Binding(
            get: { model.pendingLoginBonus != nil && sheet == nil && path.isEmpty },
            set: { if !$0 { model.pendingLoginBonus = nil } }
        )) {
            if let offer = model.pendingLoginBonus {
                LoginBonusView(offer: offer)
                    .presentationDetents([.medium])
                    .presentationCornerRadius(32)
                    .presentationBackground(Theme.background)
                    .interactiveDismissDisabled()
            }
        }
    }
}

/// Kleine Hilfe: Zurück-Button für Vollbild-Spiele.
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var beforeLeaving: () -> Void = {}

    var body: some View {
        IconButton(systemName: "chevron.left") {
            beforeLeaving()
            dismiss()
        }
        .accessibilityLabel("Zurück")
    }
}
