import SwiftUI

// MARK: - Status

/// Dezente Anzeige: 🟢 Online / ⚪ Offline
struct ConnectionBadge: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isOnline ? Theme.success : Color.white.opacity(0.55))
                .frame(width: 9, height: 9)
                .shadow(color: isOnline ? Theme.success.opacity(0.8) : .clear, radius: 4)
            Text(isOnline ? "Online" : "Offline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPanel(cornerRadius: 20)
        .accessibilityLabel(isOnline ? "Online" : "Offline")
        .animation(.easeInOut, value: isOnline)
    }
}

/// Server-Verbindungsstatus innerhalb des Multiplayer-Bereichs.
struct ServerStatusLine: View {
    @Environment(OnlineService.self) private var online

    var body: some View {
        HStack(spacing: 8) {
            switch online.state {
            case .connected:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                Text("Mit Server verbunden")
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Verbinde mit Server …")
            case .reconnecting:
                ProgressView().controlSize(.small)
                Text("Verbindung wird wiederhergestellt …")
            case .disconnected:
                Image(systemName: "bolt.horizontal.circle").foregroundStyle(Theme.textTertiary)
                Text("Nicht verbunden")
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.redBright)
                Text(reason)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Overlay während Verbindungsverlust an einem Online-Tisch.
struct ReconnectOverlay: View {
    @Environment(OnlineService.self) private var online
    var onGiveUp: () -> Void

    var body: some View {
        switch online.state {
        case .reconnecting:
            panel {
                ProgressView().controlSize(.large).tint(.white)
                Text("Verbindung verloren").font(.display(26)).foregroundStyle(.white)
                Text("Versuche Verbindung wiederherzustellen …\nDer Spielstand bleibt auf dem Server erhalten.")
                    .font(.system(size: 16)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
        case .failed(let reason):
            panel {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundStyle(Theme.redBright)
                Text(reason).font(.display(22)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Offene Züge wurden vom Server nach den Tischregeln behandelt (Stand bzw. Check/Fold). Deine Online-Chips verwaltet weiterhin der Server.")
                    .font(.system(size: 15)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Button("ZURÜCK ZUM MENÜ", action: onGiveUp).buttonStyle(.casino(.primary, size: .large))
            }
        default:
            EmptyView()
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 18) { content() }
                .padding(36)
                .frame(maxWidth: 520)
                .glassPanel(cornerRadius: 30)
        }
        .transition(.opacity)
    }
}

/// Einladung eines Freundes (erscheint oben im Menü).
struct InvitationBanner: View {
    @Environment(OnlineService.self) private var online
    let invitation: Invitation

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "envelope.open.fill").font(.system(size: 22)).foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invitation.from.displayName) lädt dich ein").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text("\(invitation.game.title) · Raum \(invitation.roomCode)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Ablehnen") { online.decline(invitation) }
                .buttonStyle(.casino(.ghost, size: .small))
            Button("Beitreten") { online.accept(invitation) }
                .buttonStyle(.casino(.primary, size: .small))
        }
        .padding(14)
        .frame(maxWidth: 620)
        .glassPanel(cornerRadius: 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

// MARK: - Mit Freunden

struct FriendsHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnlineService.self) private var online
    @Environment(ConnectivityMonitor.self) private var connectivity
    @State private var joinCode = ""
    @State private var friendCode = ""
    @State private var createGame: OnlineGame = .poker

    var body: some View {
        ZStack {
            LightSweepBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    MultiplayerHeader(title: "MIT FREUNDEN", subtitle: "Private Räume mit Einladungscode")

                    if !connectivity.isOnline {
                        OfflineNotice()
                    } else if let room = online.room {
                        RoomLobbyView(room: room)
                    } else {
                        createAndJoin
                    }
                    friendsSection
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
        }
        .onAppear { online.connect(displayName: model.profile.displayName) }
    }

    private var createAndJoin: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Raum erstellen", subtitle: "Spiel wählen, Code teilen, Freunde warten lassen.")
                Picker("Spiel", selection: $createGame) {
                    ForEach(OnlineGame.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("\(createGame.title): \(createGame.minPlayers)–\(createGame.maxPlayers) Spieler")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                Button("RAUM ERSTELLEN") { online.createRoom(createGame) }
                    .buttonStyle(.casino(.primary, size: .large, fullWidth: true))
                    .disabled(!online.isConnected)
            }
            .padding(22)
            .glassPanel(cornerRadius: 26)

            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Raum beitreten", subtitle: "Code vom Host eingeben.")
                TextField("z. B. A7K9P2", text: $joinCode)
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.4)))
                    .foregroundStyle(.white)
                    .onChange(of: joinCode) { _, value in
                        joinCode = String(value.uppercased().filter { RoomCode.alphabet.contains($0) }.prefix(RoomCode.length))
                    }
                Button("BEITRETEN") {
                    if !online.joinRoom(code: joinCode) {
                        model.show(Toast(icon: "exclamationmark.circle", title: "Ungültiger Code", subtitle: "6 Zeichen, z. B. A7K9P2", tint: Theme.red))
                    }
                }
                .buttonStyle(.casino(.gold, size: .large, fullWidth: true))
                .disabled(!online.isConnected || joinCode.count != RoomCode.length)
            }
            .padding(22)
            .glassPanel(cornerRadius: 26)
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Friends")
            if let account = online.account {
                HStack(spacing: 12) {
                    Text("Dein Freundescode:").foregroundStyle(Theme.textSecondary)
                    Text(account.player.friendCode).font(.system(size: 20, weight: .black, design: .monospaced)).foregroundStyle(Theme.goldLight)
                    ShareLink(item: "Füge mich in BlackCasino als Freund hinzu: \(account.player.friendCode)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Spacer()
                    TextField("Freundescode", text: $friendCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 160)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4)))
                    Button("HINZUFÜGEN") {
                        online.addFriend(code: friendCode)
                        friendCode = ""
                    }
                    .buttonStyle(.casino(.secondary, size: .small))
                    .disabled(friendCode.count < RoomCode.length)
                }
                .font(.system(size: 15))
            }
            if online.friends.isEmpty {
                Text("Noch keine Freunde. Tausche Freundescodes aus, um sie zu Räumen einzuladen.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(online.friends) { friend in
                HStack(spacing: 12) {
                    Circle().fill(color(friend.presence)).frame(width: 10, height: 10)
                    Text(friend.player.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Text(label(friend.presence)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if online.room != nil && friend.presence == .online {
                        Button("EINLADEN") { online.invite(friend.player.id) }
                            .buttonStyle(.casino(.gold, size: .small))
                    }
                    Menu {
                        Button("Freund entfernen", role: .destructive) { online.removeFriend(friend.player.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(14)
                .glassPanel(cornerRadius: 16)
            }
        }
    }

    private func color(_ p: Presence) -> Color {
        switch p {
        case .online: return Theme.success
        case .inGame: return Theme.gold
        case .offline: return Color.white.opacity(0.3)
        }
    }

    private func label(_ p: Presence) -> String {
        switch p {
        case .online: return "Online"
        case .inGame: return "Im Spiel"
        case .offline: return "Offline"
        }
    }
}

struct RoomLobbyView: View {
    @Environment(OnlineService.self) private var online
    let room: RoomInfo

    private var isHost: Bool { online.account?.player.id == room.hostID }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BLACKCASINO ROOM").font(.display(16, weight: .heavy)).tracking(2).foregroundStyle(Theme.gold)
                    Text("ROOM CODE").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.textTertiary)
                    Text(room.code)
                        .font(.system(size: 54, weight: .black, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(Theme.goldGradient)
                        .textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: "Spiel mit mir \(room.game.title) in BlackCasino! Raumcode: \(room.code)") {
                    Label("CODE TEILEN", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.casino(.secondary, size: .medium))
            }

            HStack(spacing: 30) {
                info("Spiel", room.game.title)
                info("Spieler", "\(room.members.count) / \(room.maxPlayers)")
                info("Status", room.status == .waiting ? (room.canStart ? "Bereit" : "Warte auf Spieler") : "Im Spiel")
            }

            if isHost && room.members.count == 1 {
                Picker("Spiel", selection: Binding(get: { room.game }, set: { online.setRoomGame($0) })) {
                    ForEach(OnlineGame.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(room.members) { member in
                    HStack {
                        Image(systemName: member.id == room.hostID ? "crown.fill" : "person.fill")
                            .foregroundStyle(member.id == room.hostID ? Theme.gold : Theme.textSecondary)
                        Text(member.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        if member.id == online.account?.player.id {
                            Text("(du)").foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                Button("RAUM VERLASSEN") { online.leaveRoom() }
                    .buttonStyle(.casino(.ghost, size: .large))
                Spacer()
                if isHost {
                    Button("START GAME") { online.startRoom() }
                        .buttonStyle(.casino(.primary, size: .large))
                        .disabled(!room.canStart || !online.isConnected)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Warte auf Host …").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if isHost && !room.canStart {
                Text("Mindestens \(room.game.minPlayers) Spieler werden benötigt.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(26)
        .glassPanel(cornerRadius: 28)
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Theme.textTertiary)
            Text(value).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Random Match

struct RandomMatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(OnlineService.self) private var online
    @Environment(ConnectivityMonitor.self) private var connectivity
    @State private var game: OnlineGame = .poker

    var body: some View {
        ZStack {
            LightSweepBackground()
            VStack(alignment: .leading, spacing: 26) {
                MultiplayerHeader(title: "RANDOM MATCH", subtitle: "Zuerst echte Spieler, sonst auf Wunsch faire Bots")
                Spacer()
                Group {
                    if !connectivity.isOnline {
                        OfflineNotice()
                    } else {
                        switch online.matchmaking {
                        case .searching(let g, let since):
                            searching(g, since: since)
                        case .noMatchFound:
                            noMatch
                        case .idle, .matched:
                            chooser
                        }
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                Spacer()
                Text("Bots sehen nur ihre eigenen Karten und das, was alle am Tisch sehen. Sie beeinflussen weder Karten noch Ergebnisse.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .onAppear { online.connect(displayName: model.profile.displayName) }
        .onDisappear {
            if case .searching = online.matchmaking { online.cancelMatch() }
            if case .noMatchFound = online.matchmaking { online.cancelMatch() }
        }
    }

    private var chooser: some View {
        VStack(spacing: 22) {
            Picker("Spiel", selection: $game) {
                ForEach(OnlineGame.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(game == .poker ? "Texas Hold'em · Blinds 10/20 · Buy-in bis 2.000 Online-Chips"
                                : "Blackjack · gemeinsamer Dealer · Einsatz 10–1.000 Online-Chips")
                .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            Button("SPIELER SUCHEN") { online.findMatch(game) }
                .buttonStyle(.casino(.primary, size: .large, fullWidth: true))
                .disabled(!online.isConnected)
            ServerStatusLine()
        }
        .padding(30)
        .glassPanel(cornerRadius: 30)
    }

    private func searching(_ game: OnlineGame, since: Date) -> some View {
        VStack(spacing: 22) {
            ProgressView().controlSize(.large).tint(Theme.red)
            Text("Suche nach Spielern …").font(.display(26)).foregroundStyle(.white)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(game.title) · \(max(0, Int(context.date.timeIntervalSince(since)))) s")
                    .font(.numeric(16)).foregroundStyle(Theme.textSecondary)
            }
            Button("ABBRECHEN") { online.cancelMatch() }
                .buttonStyle(.casino(.secondary, size: .large))
        }
        .padding(34)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 30)
    }

    private var noMatch: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash").font(.system(size: 40)).foregroundStyle(Theme.gold)
            Text("Kein Spieler gefunden. Mit Bots spielen?").font(.display(22)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Button("JA") { online.playWithBots() }
                    .buttonStyle(.casino(.primary, size: .large))
                Button("WARTEN") { online.keepWaiting() }
                    .buttonStyle(.casino(.secondary, size: .large))
            }
            Button("Abbrechen") { online.cancelMatch() }
                .buttonStyle(.casino(.ghost, size: .small))
        }
        .padding(34)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 30)
    }
}

// MARK: - Gemeinsame Bausteine

struct MultiplayerHeader: View {
    @Environment(OnlineService.self) private var online
    @Environment(ConnectivityMonitor.self) private var connectivity
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            BackButton()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(22)).tracking(3).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let account = online.account {
                OnlineChipsView(amount: account.onlineChips)
            }
            ConnectionBadge(isOnline: connectivity.isOnline)
        }
        .padding(.top, 18)
    }
}

/// Online-Chips (vom Server verwaltet, ebenfalls ohne Geldwert).
struct OnlineChipsView: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 8) {
            ChipIcon(color: Theme.gold, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("ONLINE-CHIPS").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Theme.textTertiary)
                Text(ChipFormat.string(amount)).font(.numeric(17, weight: .heavy)).foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(amount)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassPanel(cornerRadius: 30)
        .accessibilityLabel("Online-Chips \(amount)")
    }
}

struct OfflineNotice: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.system(size: 28)).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Für Multiplayer wird eine Internetverbindung benötigt.")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("Blackjack, Poker gegen Bots und Slots kannst du offline weiterspielen.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24)
    }
}
