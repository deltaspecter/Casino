import SwiftUI
import Observation
import CasinoCore

@MainActor
@Observable
final class SlotsViewModel {
    struct ReelColumn {
        /// Symbole von oben nach unten (inkl. je eines Puffersymbols oben und unten).
        var symbols: [String]
        /// Verschiebung in Zellen: 1 = Ruheposition (oberes Puffersymbol verdeckt).
        var offset: CGFloat
        var isSpinning = false
    }

    struct Celebration: Equatable {
        let title: String
        let amount: Int
    }

    let definition: SlotMachineDefinition
    let theme: SlotTheme
    private let machine: SlotMachine

    var lineBetIndex = 1
    private(set) var reels: [ReelColumn] = []
    private(set) var isSpinning = false
    private(set) var lastResult: SpinResult?
    private(set) var highlighted: Set<SlotPosition> = []
    private(set) var activeLine: LineWin?
    private(set) var displayedWin = 0
    /// Bereits gutgeschriebener, aber noch nicht angezeigter Gewinn (Walzen drehen noch).
    private(set) var pendingWin = 0
    private(set) var celebration: Celebration?

    @ObservationIgnored private var stops: [Int]
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var lineCycleTask: Task<Void, Never>?

    init(machineID: String, app: AppModel) {
        let def = SlotCatalog.all.first { $0.id == machineID } ?? SlotCatalog.crimsonSevens
        definition = def
        machine = SlotMachine(definition: def)
        theme = SlotTheme.forMachine(def.id)
        self.app = app
        // Startbild: zufällige Walzenpositionen (nur Optik, kein Spielergebnis)
        stops = def.reelStrips.map { app.random.uniform($0.count) }
        reels = stops.enumerated().map { reel, stop in
            let strip = def.reelStrips[reel]
            let n = strip.count
            let symbols = (-1...def.rows).map { strip[((stop + $0) % n + n) % n] }
            return ReelColumn(symbols: symbols, offset: 1)
        }
        lineBetIndex = min(1, def.lineBetOptions.count - 1)
    }

    var lineBet: Int { definition.lineBetOptions[lineBetIndex] }
    var totalBet: Int { lineBet * definition.paylines.count }

    func changeBet(by delta: Int) {
        guard !isSpinning else { return }
        let next = min(max(lineBetIndex + delta, 0), definition.lineBetOptions.count - 1)
        guard next != lineBetIndex else { return }
        lineBetIndex = next
        Haptics.selection()
    }

    // MARK: - Drehen

    func spin() async {
        guard !isSpinning, let app else { return }
        guard app.debit(totalBet) else { return }

        isSpinning = true
        lineCycleTask?.cancel()
        highlighted = []
        activeLine = nil
        displayedWin = 0
        celebration = nil
        Haptics.thud()

        // Das Ergebnis wird sofort und unabhängig berechnet und verbucht.
        // Die Animation zeigt es nur an.
        let result = machine.spin(lineBet: lineBet, random: app.random)
        lastResult = result
        if result.totalPayout > 0 {
            pendingWin = result.totalPayout
            app.credit(result.totalPayout)
        }
        app.record(.slotSpin(bet: result.totalBet, payout: result.totalPayout))

        // Walzen-Spalten so aufbauen, dass sie physisch korrekt vom alten zum neuen Stopp laufen
        for i in reels.indices {
            let strip = definition.reelStrips[i]
            let n = strip.count
            let old = stops[i], new = result.stops[i]
            let distance = ((old - new) % n + n) % n + (1 + i / 2) * n
            let count = distance + definition.rows
            var column = [strip[((new - 1) % n + n) % n]]
            column += (0..<count).map { strip[(new + $0) % n] }
            column.append(strip[(old + definition.rows) % n])
            reels[i] = ReelColumn(symbols: column, offset: CGFloat(distance + 1), isSpinning: true)
        }
        stops = result.stops

        // Alle Walzen starten gemeinsam und stoppen nacheinander
        let reducedMotion = app.profile.settings.reducedMotion
        let base = reducedMotion ? 0.6 : 1.1
        let step = reducedMotion ? 0.15 : 0.32
        // Einen Frame rendern lassen, bevor die Bewegung startet
        try? await Task.sleep(for: .milliseconds(30))
        for i in reels.indices {
            let duration = base + step * Double(i)
            withAnimation(.timingCurve(0.25, 0.0, 0.2, 1.0, duration: duration)) {
                reels[i].offset = 0.86
            }
        }
        var elapsed = 0.0
        for i in reels.indices {
            let duration = base + step * Double(i)
            try? await Task.sleep(for: .seconds(duration - elapsed))
            elapsed = duration
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                reels[i].offset = 1
                reels[i].isSpinning = false
            }
            Haptics.tap()
        }
        try? await Task.sleep(for: .milliseconds(250))

        // Ruhezustand: nur sichtbares Fenster + Puffer behalten
        for i in reels.indices {
            let strip = definition.reelStrips[i]
            let n = strip.count
            reels[i] = ReelColumn(symbols: (-1...definition.rows).map { strip[((stops[i] + $0) % n + n) % n] }, offset: 1)
        }
        isSpinning = false
        await presentWin(result)
    }

    private func presentWin(_ result: SpinResult) async {
        guard result.isWin else {
            pendingWin = 0
            return
        }
        var positions = Set(result.lineWins.flatMap(\.positions))
        positions.formUnion(result.scatterPositions)
        withAnimation(.easeOut(duration: 0.25)) { highlighted = positions }

        if result.winMultiplier >= 15 {
            celebration = Celebration(title: result.winMultiplier >= 50 ? "MEGA WIN" : "BIG WIN", amount: result.totalPayout)
            Haptics.success()
        } else {
            Haptics.success()
        }

        // Gewinn hochzählen
        let steps = 20
        for k in 1...steps {
            displayedWin = result.totalPayout * k / steps
            pendingWin = result.totalPayout - displayedWin
            try? await Task.sleep(for: .milliseconds(30))
        }
        pendingWin = 0

        // Gewinnlinien nacheinander hervorheben
        let wins = result.lineWins
        guard !wins.isEmpty else { return }
        lineCycleTask = Task { @MainActor [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.2)) { self.activeLine = wins[index % wins.count] }
                index += 1
                try? await Task.sleep(for: .seconds(wins.count == 1 ? 3 : 1.3))
                if wins.count == 1 && index > 1 { break }
            }
        }
        if celebration != nil {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.4)) { celebration = nil }
        }
    }

    func stopEffects() {
        lineCycleTask?.cancel()
        pendingWin = 0
    }
}
