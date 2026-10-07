import SwiftUI

/// BlackCasino – ein reines Unterhaltungsspiel mit virtuellen Chips.
/// Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen und keinen Umtausch.
@main
struct BlackCasinoApp: App {
    @State private var model = AppModel()
    @State private var connectivity = ConnectivityMonitor()
    @State private var online = OnlineService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(connectivity)
                .environment(online)
                .onAppear(perform: setUpOnline)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.save()
                // Außerhalb eines Online-Tisches trennen; am Tisch hält der Server den Platz für eine Gnadenfrist.
                if !online.isAtTable { online.disconnect() }
            case .inactive:
                model.save()
            case .active:
                if model.phase == .lobby {
                    model.refreshDay()
                    if connectivity.isOnline { online.connect(displayName: model.profile.displayName) }
                }
            @unknown default:
                break
            }
        }
    }

    /// Verbindungserkennung und Online-Hinweise einrichten. Offline-Spiele sind davon unabhängig.
    private func setUpOnline() {
        let online = self.online, model = self.model, connectivity = self.connectivity
        connectivity.onChange = { isOnline in
            if isOnline {
                online.networkRestored()
                model.show(Toast(icon: "wifi", title: "Du bist wieder online.", subtitle: "Multiplayer ist verfügbar.", tint: Theme.success))
            } else {
                online.networkLost()
                model.show(Toast(icon: "wifi.slash", title: "Offline-Modus aktiv",
                                 subtitle: "Blackjack, Poker gegen Bots und Slots funktionieren weiter.", tint: Theme.textSecondary))
            }
        }
        online.onNotice = { text, isError in
            model.show(Toast(icon: isError ? "exclamationmark.circle.fill" : "info.circle.fill", title: text, subtitle: nil,
                             tint: isError ? Theme.red : Theme.gold))
        }
        connectivity.start()
    }
}
