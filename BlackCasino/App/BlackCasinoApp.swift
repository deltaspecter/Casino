import SwiftUI

/// BlackCasino – ein reines Unterhaltungsspiel mit virtuellen Chips.
/// Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen und keinen Umtausch.
@main
struct BlackCasinoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                model.save()
            case .active:
                if model.phase == .lobby { model.refreshDay() }
            @unknown default:
                break
            }
        }
    }
}
