import Foundation

/// Die Automaten von BlackCasino. Alle Werte sind fest definiert und öffentlich einsehbar;
/// die theoretische Auszahlungsquote wird mit `SlotMath` exakt berechnet und im Spiel angezeigt.
public enum SlotCatalog {
    public static let all: [SlotMachineDefinition] = [crimsonSevens, midnightGems, dragonFortune]

    /// 10 Gewinnlinien für ein 5×3-Raster (Zeile 0 = oben).
    public static let standardPaylines: [[Int]] = [
        [1, 1, 1, 1, 1],
        [0, 0, 0, 0, 0],
        [2, 2, 2, 2, 2],
        [0, 1, 2, 1, 0],
        [2, 1, 0, 1, 2],
        [1, 0, 0, 0, 1],
        [1, 2, 2, 2, 1],
        [0, 0, 1, 2, 2],
        [2, 2, 1, 0, 0],
        [1, 2, 1, 0, 1]
    ]

    public static let crimsonSevens = SlotMachineDefinition(
        id: "crimson-sevens",
        name: "Crimson Sevens",
        tagline: "Der rote Klassiker",
        symbols: [
            SlotSymbol("cherry", pays: [3: 7, 4: 20, 5: 65]),
            SlotSymbol("lemon", pays: [3: 7, 4: 20, 5: 65]),
            SlotSymbol("plum", pays: [3: 10, 4: 34, 5: 100]),
            SlotSymbol("bell", pays: [3: 17, 4: 60, 5: 170]),
            SlotSymbol("bar", pays: [3: 30, 4: 100, 5: 340]),
            SlotSymbol("seven", pays: [3: 65, 4: 250, 5: 1250]),
            SlotSymbol("wild", kind: .wild, pays: [3: 125, 4: 500, 5: 3000]),
            SlotSymbol("scatter", kind: .scatter, pays: [3: 2, 4: 10, 5: 50])
        ],
        reelStrips: (0..<5).map { reel in
            makeStrip(reel: reel, weights: [
                ("cherry", 7), ("lemon", 7), ("plum", 6), ("bell", 5),
                ("bar", 4), ("seven", 2), ("wild", 1), ("scatter", 1)
            ])
        },
        paylines: standardPaylines,
        rows: 3,
        lineBetOptions: [1, 2, 5, 10, 25, 50, 100]
    )

    public static let midnightGems = SlotMachineDefinition(
        id: "midnight-gems",
        name: "Midnight Gems",
        tagline: "Edelsteine im Mondlicht",
        symbols: [
            SlotSymbol("topaz", pays: [3: 6, 4: 16, 5: 56]),
            SlotSymbol("amethyst", pays: [3: 8, 4: 22, 5: 72]),
            SlotSymbol("emerald", pays: [3: 11, 4: 35, 5: 112]),
            SlotSymbol("sapphire", pays: [3: 16, 4: 56, 5: 176]),
            SlotSymbol("ruby", pays: [3: 29, 4: 112, 5: 400]),
            SlotSymbol("diamond", pays: [3: 56, 4: 224, 5: 960]),
            SlotSymbol("wild", kind: .wild, pays: [3: 100, 4: 400, 5: 2400]),
            SlotSymbol("scatter", kind: .scatter, pays: [3: 2, 4: 12, 5: 60])
        ],
        reelStrips: (0..<5).map { reel in
            makeStrip(reel: reel, weights: [
                ("topaz", 8), ("amethyst", 7), ("emerald", 6), ("sapphire", 5),
                ("ruby", 3), ("diamond", 2), ("wild", 1), ("scatter", 1)
            ])
        },
        paylines: standardPaylines,
        rows: 3,
        lineBetOptions: [1, 2, 5, 10, 25, 50, 100]
    )

    public static let dragonFortune = SlotMachineDefinition(
        id: "dragon-fortune",
        name: "Dragon Fortune",
        tagline: "Hohe Volatilität, große Momente",
        symbols: [
            SlotSymbol("coin", pays: [3: 5, 4: 15, 5: 45]),
            SlotSymbol("lantern", pays: [3: 6, 4: 18, 5: 60]),
            SlotSymbol("fan", pays: [3: 9, 4: 30, 5: 90]),
            SlotSymbol("koi", pays: [3: 15, 4: 60, 5: 190]),
            SlotSymbol("tiger", pays: [3: 38, 4: 150, 5: 600]),
            SlotSymbol("dragon", pays: [3: 90, 4: 450, 5: 2250]),
            SlotSymbol("wild", kind: .wild, pays: [3: 150, 4: 750, 5: 7500]),
            SlotSymbol("scatter", kind: .scatter, pays: [3: 3, 4: 15, 5: 100])
        ],
        reelStrips: (0..<5).map { reel in
            makeStrip(reel: reel, weights: [
                ("coin", 8), ("lantern", 7), ("fan", 6), ("koi", 4),
                ("tiger", 3), ("dragon", 1), ("wild", 1), ("scatter", 1)
            ])
        },
        paylines: standardPaylines,
        rows: 3,
        lineBetOptions: [1, 2, 5, 10, 25, 50, 100]
    )

    /// Erzeugt einen festen, gleichmäßig verteilten Walzenstreifen.
    /// Deterministisch – der Streifen ist für jede Drehung derselbe, nur die Stoppposition ist zufällig.
    static func makeStrip(reel: Int, weights: [(String, Int)]) -> [String] {
        let length = weights.reduce(0) { $0 + $1.1 }
        var slots = [String?](repeating: nil, count: length)
        // Seltene Symbole zuerst platzieren, damit sie gut verteilt sind
        for (index, (symbol, count)) in weights.enumerated().sorted(by: { $0.element.1 < $1.element.1 }) {
            let spacing = Double(length) / Double(count)
            let offset = Double((reel * 7 + index * 3) % length)
            for k in 0..<count {
                var position = Int((offset + Double(k) * spacing).rounded()) % length
                while slots[position] != nil { position = (position + 1) % length }
                slots[position] = symbol
            }
        }
        return slots.map { $0! }
    }
}
