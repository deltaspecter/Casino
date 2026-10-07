import Foundation

/// Exakte (nicht simulierte) Berechnung der theoretischen Auszahlungsquote.
/// Dient der Transparenz: Die angezeigte Quote ergibt sich allein aus
/// Walzenstreifen und Auszahlungstabelle.
public enum SlotMath {
    public struct Report {
        /// Return to Player (z. B. 0.95 = 95 %)
        public let rtp: Double
        public let lineReturn: Double
        public let scatterReturn: Double
    }

    public static func report(for definition: SlotMachineDefinition) -> Report {
        let machine = SlotMachine(definition: definition)

        // Wahrscheinlichkeit je Symbol und Walze an einer festen Zeile
        let probabilities: [[(String, Double)]] = definition.reelStrips.map { strip in
            var counts: [String: Int] = [:]
            for s in strip { counts[s, default: 0] += 1 }
            return counts.map { ($0.key, Double($0.value) / Double(strip.count)) }.sorted { $0.0 < $1.0 }
        }

        // Erwartungswert einer Linie (in Linieneinsätzen) über alle Symbolkombinationen
        var lineEV = 0.0
        var current: [String] = []
        func recurse(_ reel: Int, _ p: Double) {
            if reel == probabilities.count {
                if let win = machine.evaluateLine(current) { lineEV += p * Double(win.multiplier) }
                return
            }
            for (symbol, q) in probabilities[reel] {
                current.append(symbol)
                recurse(reel + 1, p * q)
                current.removeLast()
            }
        }
        recurse(0, 1)

        // Scatter: Verteilung der Scatter-Anzahl je Walzenfenster, dann Faltung
        var scatterEV = 0.0
        if let scatter = definition.symbols.first(where: { $0.kind == .scatter }) {
            var distribution: [Double] = [1]
            for (reel, strip) in definition.reelStrips.enumerated() {
                var perReel = [Double](repeating: 0, count: definition.rows + 1)
                for stop in strip.indices {
                    let n = machine.window(reel: reel, stop: stop).filter { $0 == scatter.id }.count
                    perReel[n] += 1.0 / Double(strip.count)
                }
                var next = [Double](repeating: 0, count: distribution.count + definition.rows)
                for (a, pa) in distribution.enumerated() where pa > 0 {
                    for (b, pb) in perReel.enumerated() where pb > 0 { next[a + b] += pa * pb }
                }
                distribution = next
            }
            for (n, p) in distribution.enumerated() {
                scatterEV += p * Double(scatter.payout(for: min(n, 5)))
            }
        }
        return Report(rtp: lineEV + scatterEV, lineReturn: lineEV, scatterReturn: scatterEV)
    }
}
