import Foundation

public enum SlotSymbolKind: String, Codable {
    case regular, wild, scatter
}

public struct SlotSymbol: Hashable, Codable, Identifiable {
    public let id: String
    public let kind: SlotSymbolKind
    /// Auszahlung pro Linieneinsatz für 3, 4 bzw. 5 Treffer (Scatter: × Gesamteinsatz).
    public let pays: [Int: Int]

    public init(_ id: String, kind: SlotSymbolKind = .regular, pays: [Int: Int]) {
        self.id = id
        self.kind = kind
        self.pays = pays
    }

    public func payout(for count: Int) -> Int { pays[count] ?? 0 }
}

/// Konfiguration eines Automaten: Walzenstreifen, Gewinnlinien und Auszahlungstabelle.
public struct SlotMachineDefinition: Identifiable {
    public let id: String
    public let name: String
    public let tagline: String
    public let symbols: [SlotSymbol]
    /// Pro Walze die physische Symbolfolge (Index in `symbols`).
    public let reelStrips: [[String]]
    /// Jede Linie: Zeilenindex (0 = oben) je Walze.
    public let paylines: [[Int]]
    public let rows: Int
    public let lineBetOptions: [Int]

    public var reelCount: Int { reelStrips.count }

    public func symbol(_ id: String) -> SlotSymbol {
        symbols.first { $0.id == id }!
    }
}

public struct LineWin: Equatable, Identifiable {
    public let lineIndex: Int
    public let symbolID: String
    public let count: Int
    public let payout: Int
    /// Positionen (Walze, Zeile) der gewinnenden Symbole.
    public let positions: [SlotPosition]
    public var id: Int { lineIndex }
}

public struct SlotPosition: Hashable {
    public let reel: Int
    public let row: Int
}

public struct SpinResult: Equatable {
    /// Stoppposition je Walze auf ihrem Streifen.
    public let stops: [Int]
    /// Sichtbares Raster `[walze][zeile]` als Symbol-IDs.
    public let grid: [[String]]
    public let lineWins: [LineWin]
    public let scatterCount: Int
    public let scatterPayout: Int
    public let scatterPositions: [SlotPosition]
    public let totalBet: Int

    public var totalPayout: Int { lineWins.reduce(0) { $0 + $1.payout } + scatterPayout }
    public var isWin: Bool { totalPayout > 0 }
    public var winMultiplier: Double { totalBet > 0 ? Double(totalPayout) / Double(totalBet) : 0 }
}

/// Spielautomat. Jede Walze stoppt an einer **unabhängig und gleichverteilt**
/// gezogenen Position ihres Streifens. Es gibt keinen Zustand zwischen Drehungen,
/// keine Gewinnserien-Steuerung und keine Abhängigkeit vom Kontostand.
public struct SlotMachine {
    public let definition: SlotMachineDefinition

    public init(definition: SlotMachineDefinition) {
        self.definition = definition
    }

    public func spin(lineBet: Int, random: RandomSource) -> SpinResult {
        let stops = definition.reelStrips.map { random.uniform($0.count) }
        return evaluate(stops: stops, lineBet: lineBet)
    }

    /// Sichtbare Symbole einer Walze, wenn sie an `stop` hält (oberste Zeile = `stop`).
    public func window(reel: Int, stop: Int) -> [String] {
        let strip = definition.reelStrips[reel]
        return (0..<definition.rows).map { strip[(stop + $0) % strip.count] }
    }

    public func evaluate(stops: [Int], lineBet: Int) -> SpinResult {
        let grid = stops.enumerated().map { window(reel: $0.offset, stop: $0.element) }
        let totalBet = lineBet * definition.paylines.count

        var lineWins: [LineWin] = []
        for (lineIndex, line) in definition.paylines.enumerated() {
            let symbols = line.enumerated().map { grid[$0.offset][$0.element] }
            if let win = evaluateLine(symbols) {
                let positions = (0..<win.count).map { SlotPosition(reel: $0, row: line[$0]) }
                lineWins.append(LineWin(lineIndex: lineIndex, symbolID: win.symbol, count: win.count,
                                        payout: win.multiplier * lineBet, positions: positions))
            }
        }

        var scatterPositions: [SlotPosition] = []
        var scatterPayout = 0
        if let scatter = definition.symbols.first(where: { $0.kind == .scatter }) {
            for (reel, column) in grid.enumerated() {
                for (row, id) in column.enumerated() where id == scatter.id {
                    scatterPositions.append(SlotPosition(reel: reel, row: row))
                }
            }
            scatterPayout = scatter.payout(for: min(scatterPositions.count, 5)) * totalBet
        }

        return SpinResult(stops: stops, grid: grid, lineWins: lineWins,
                          scatterCount: scatterPositions.count,
                          scatterPayout: scatterPayout,
                          scatterPositions: scatterPayout > 0 ? scatterPositions : [],
                          totalBet: totalBet)
    }

    /// Wertet eine Linie von links nach rechts aus. Wilds ersetzen alle regulären Symbole.
    /// Gezahlt wird die höhere von „reiner Wild-Kette“ und „ersetztem Symbol“.
    public func evaluateLine(_ symbols: [String]) -> (symbol: String, count: Int, multiplier: Int)? {
        let wildID = definition.symbols.first { $0.kind == .wild }?.id
        let scatterID = definition.symbols.first { $0.kind == .scatter }?.id

        // Reine Wild-Kette
        var wildRun = 0
        if let wildID {
            for s in symbols { if s == wildID { wildRun += 1 } else { break } }
        }
        var best: (symbol: String, count: Int, multiplier: Int)?
        if let wildID, wildRun >= 3 {
            let pay = definition.symbol(wildID).payout(for: wildRun)
            if pay > 0 { best = (wildID, wildRun, pay) }
        }

        // Erstes Nicht-Wild-Symbol bestimmt die Linie
        guard let target = symbols.first(where: { $0 != wildID }), target != scatterID else { return best }
        var count = 0
        for s in symbols {
            if s == target || s == wildID { count += 1 } else { break }
        }
        let pay = definition.symbol(target).payout(for: count)
        if pay > 0 && pay > (best?.multiplier ?? 0) {
            best = (target, count, pay)
        }
        return best
    }
}
