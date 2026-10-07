import Foundation
import Network
import Observation

/// Erkennt automatisch, ob eine Internetverbindung besteht (ONLINE/OFFLINE).
/// Offline-Spiele (Blackjack, Poker gegen Bots, Slots) hängen davon nicht ab.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true
    /// Wird bei jedem Wechsel aufgerufen (für dezente Hinweise).
    @ObservationIgnored var onChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "BlackCasino.Connectivity")
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
