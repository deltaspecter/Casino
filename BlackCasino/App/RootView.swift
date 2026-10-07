import SwiftUI
import CasinoCore

enum Route: Hashable {
    case blackjack
    case poker
    case slotsLobby
    case slotMachine(id: String)
    case friends
    case randomMatch
    case onlineTable
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
    @Environment(OnlineService.self) private var online
    @Environment(ConnectivityMonitor.self) private var connectivity
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
                        case .friends: FriendsHubView()
                        case .randomMatch: RandomMatchView()
                        case .onlineTable: OnlineTableView()
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
        .overlay(alignment: .top) {
            // Einladungen von Freunden (nur außerhalb laufender Spiele)
            if let invitation = online.invitations.last, !path.contains(.onlineTable) {
                InvitationBanner(invitation: invitation)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: online.invitations)
        // Server hat einen Tisch zugewiesen (Raumstart oder Match): Tisch öffnen
        .onChange(of: online.table?.tableID) { _, tableID in
            guard tableID != nil, path.last != .onlineTable else { return }
            path.removeAll { $0 == .onlineTable }
            path.append(.onlineTable)
        }
        .onAppear {
            if connectivity.isOnline { online.connect(displayName: model.profile.displayName) }
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
