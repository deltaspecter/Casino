import SwiftUI
import UIKit

/// Zentrales Design-System: dunkle Flächen, kräftiges Rot, dezentes Gold.
enum Theme {
    // MARK: Farben
    static let background = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let surface = Color(red: 0.085, green: 0.085, blue: 0.10)
    static let surfaceRaised = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let stroke = Color.white.opacity(0.08)

    static let red = Color(red: 0.86, green: 0.07, blue: 0.16)
    static let redBright = Color(red: 1.0, green: 0.22, blue: 0.28)
    static let redDeep = Color(red: 0.42, green: 0.02, blue: 0.07)

    static let gold = Color(red: 0.83, green: 0.68, blue: 0.40)
    static let goldLight = Color(red: 0.97, green: 0.87, blue: 0.62)
    static let goldDark = Color(red: 0.55, green: 0.42, blue: 0.20)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let success = Color(red: 0.25, green: 0.85, blue: 0.50)

    // UIKit-Varianten für SceneKit-Texturen
    static let uiRed = UIColor(red: 0.86, green: 0.07, blue: 0.16, alpha: 1)
    static let uiRedDeep = UIColor(red: 0.42, green: 0.02, blue: 0.07, alpha: 1)
    static let uiGold = UIColor(red: 0.83, green: 0.68, blue: 0.40, alpha: 1)
    static let uiGoldLight = UIColor(red: 0.97, green: 0.87, blue: 0.62, alpha: 1)

    // MARK: Verläufe
    static let redGradient = LinearGradient(colors: [redBright, red, redDeep],
                                            startPoint: .top, endPoint: .bottom)
    static let goldGradient = LinearGradient(colors: [goldLight, gold, goldDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let surfaceGradient = LinearGradient(colors: [surfaceRaised, surface],
                                                startPoint: .top, endPoint: .bottom)
    static let backdrop = RadialGradient(colors: [Color(red: 0.20, green: 0.02, blue: 0.05), background],
                                         center: .top, startRadius: 0, endRadius: 900)

    // MARK: Abstände & Radien
    static let cornerLarge: CGFloat = 28
    static let cornerMedium: CGFloat = 18
    static let cornerSmall: CGFloat = 12
    static let gutter: CGFloat = 24
}

extension Font {
    /// Große, breite Display-Schrift für Logos und Überschriften.
    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }

    /// Ziffern mit fester Breite (Kontostand, Einsätze).
    static func numeric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

enum ChipFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.maximumFractionDigits = 0
        return f
    }()

    static func string(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func signed(_ value: Int) -> String {
        (value > 0 ? "+" : value < 0 ? "−" : "±") + string(abs(value))
    }

    /// Kompakte Darstellung für Chips im 3D-Raum und kleine Labels (z. B. „12,5K“).
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        case 10_000...:
            return "\(value / 1_000)K"
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000).replacingOccurrences(of: ".", with: ",")
        default:
            return "\(value)"
        }
    }
}
