import SwiftUI
import CasinoCore

/// Gestaltung der Automaten (Farben und Symbol-Darstellung). Die Spiellogik liegt in `CasinoCore`.
struct SlotTheme {
    let accent: Color
    let glow: Color
    let background: [Color]
    let paylineColors: [Color]

    static func forMachine(_ id: String) -> SlotTheme {
        switch id {
        case "midnight-gems":
            return SlotTheme(accent: Color(red: 0.55, green: 0.35, blue: 1.0),
                             glow: Color(red: 0.4, green: 0.6, blue: 1.0),
                             background: [Color(red: 0.05, green: 0.04, blue: 0.14), Color(red: 0.01, green: 0.01, blue: 0.04)],
                             paylineColors: lineColors)
        case "dragon-fortune":
            return SlotTheme(accent: Color(red: 1.0, green: 0.55, blue: 0.1),
                             glow: Theme.gold,
                             background: [Color(red: 0.2, green: 0.04, blue: 0.02), Color(red: 0.05, green: 0.01, blue: 0.0)],
                             paylineColors: lineColors)
        default:
            return SlotTheme(accent: Theme.red, glow: Theme.redBright,
                             background: [Color(red: 0.18, green: 0.01, blue: 0.04), Color(red: 0.03, green: 0.0, blue: 0.01)],
                             paylineColors: lineColors)
        }
    }

    private static let lineColors: [Color] = [
        Theme.goldLight, Theme.redBright, .cyan, .green, .orange, .pink, .yellow, .mint, .purple, .white
    ]
}

/// Darstellung eines einzelnen Symbols.
struct SlotSymbolView: View {
    let symbolID: String
    let size: CGFloat
    var highlighted = false

    var body: some View {
        let art = SymbolArt.for(symbolID)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(highlighted ? 0.22 : 0.07), Color.white.opacity(0.01)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(highlighted ? art.colors.first!.opacity(0.9) : Color.white.opacity(0.06),
                                      lineWidth: highlighted ? 3 : 1)
                )
            art.glyphView(size: size)
        }
        .frame(width: size, height: size)
        .shadow(color: highlighted ? art.colors.first!.opacity(0.8) : .clear, radius: highlighted ? 16 : 0)
        .scaleEffect(highlighted ? 1.06 : 1)
    }
}

struct SymbolArt {
    enum Glyph {
        case sf(String)
        case text(String)
        case emoji(String)
    }

    let glyph: Glyph
    let colors: [Color]
    var label: String?

    @ViewBuilder
    func glyphView(size: CGFloat) -> some View {
        let gradient = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        VStack(spacing: 0) {
            switch glyph {
            case .sf(let name):
                Image(systemName: name)
                    .font(.system(size: size * (label == nil ? 0.5 : 0.4), weight: .bold))
                    .foregroundStyle(gradient)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
            case .text(let text):
                Text(text)
                    .font(.system(size: size * (text.count > 2 ? 0.28 : 0.6), weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(gradient)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
                    .minimumScaleFactor(0.5)
            case .emoji(let e):
                Text(e).font(.system(size: size * 0.52))
            }
            if let label {
                Text(label)
                    .font(.system(size: size * 0.13, weight: .black))
                    .tracking(1)
                    .foregroundStyle(gradient)
            }
        }
    }

    static func `for`(_ id: String) -> SymbolArt {
        let gold = [Theme.goldLight, Theme.gold, Theme.goldDark]
        let red = [Theme.redBright, Theme.red, Theme.redDeep]
        switch id {
        // Crimson Sevens
        case "cherry": return SymbolArt(glyph: .emoji("🍒"), colors: red)
        case "lemon": return SymbolArt(glyph: .emoji("🍋"), colors: [.yellow, .orange])
        case "plum": return SymbolArt(glyph: .emoji("🍇"), colors: [.purple, .indigo])
        case "bell": return SymbolArt(glyph: .sf("bell.fill"), colors: gold)
        case "bar": return SymbolArt(glyph: .text("BAR"), colors: [.white, Color(white: 0.6)])
        case "seven": return SymbolArt(glyph: .text("7"), colors: red)
        // Midnight Gems
        case "topaz": return SymbolArt(glyph: .sf("hexagon.fill"), colors: [.yellow, .orange])
        case "amethyst": return SymbolArt(glyph: .sf("octagon.fill"), colors: [Color(red: 0.8, green: 0.5, blue: 1), .purple])
        case "emerald": return SymbolArt(glyph: .sf("shield.fill"), colors: [.mint, .green])
        case "sapphire": return SymbolArt(glyph: .sf("drop.fill"), colors: [.cyan, .blue])
        case "ruby": return SymbolArt(glyph: .sf("heart.fill"), colors: red)
        case "diamond": return SymbolArt(glyph: .sf("diamond.fill"), colors: [.white, .cyan])
        // Dragon Fortune
        case "coin": return SymbolArt(glyph: .emoji("🪙"), colors: gold)
        case "lantern": return SymbolArt(glyph: .emoji("🏮"), colors: red)
        case "fan": return SymbolArt(glyph: .emoji("🎐"), colors: [.cyan, .blue])
        case "koi": return SymbolArt(glyph: .emoji("🎏"), colors: red)
        case "tiger": return SymbolArt(glyph: .emoji("🐯"), colors: [.orange, .yellow])
        case "dragon": return SymbolArt(glyph: .emoji("🐉"), colors: [.green, .mint])
        // Gemeinsame Sondersymbole
        case "wild": return SymbolArt(glyph: .sf("crown.fill"), colors: gold, label: "WILD")
        case "scatter": return SymbolArt(glyph: .sf("sparkles"), colors: [.white, Theme.goldLight, Theme.gold], label: "SCATTER")
        default: return SymbolArt(glyph: .sf("questionmark"), colors: [.white])
        }
    }
}

/// Exakt berechnete Auszahlungsquoten (einmalig beim Start ermittelt).
enum SlotInfo {
    static let reports: [String: SlotMath.Report] = {
        var result: [String: SlotMath.Report] = [:]
        for def in SlotCatalog.all { result[def.id] = SlotMath.report(for: def) }
        return result
    }()

    static func rtpText(_ id: String) -> String {
        guard let r = reports[id] else { return "–" }
        return String(format: "%.1f %%", r.rtp * 100).replacingOccurrences(of: ".", with: ",")
    }
}
