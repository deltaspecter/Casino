import UIKit
import CasinoCore

/// Zeichnet realistische Spielkarten: weißer Kartenkörper, Serifen-Indizes in den Ecken,
/// klassische Pip-Anordnung (eine Herz-7 zeigt sieben Herzen) und gespiegelte Bildkarten.
/// Farbsymbole sind Vektorpfade – sie können nicht versehentlich als Emoji erscheinen.
enum CardArt {
    /// Pixelgröße der Kartentextur (Seitenverhältnis einer Pokerkarte 63,5 × 88,9 mm).
    static let size = CGSize(width: 384, height: 538)

    static let red = UIColor(red: 0.78, green: 0.06, blue: 0.11, alpha: 1)
    static let black = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)

    static func color(for suit: Suit) -> UIColor { suit.isRed ? red : black }

    // MARK: - Farbsymbole

    /// Pfad eines Farbsymbols im Rechteck `rect` (Spitze oben, außer beim Herz).
    static func suitPath(_ suit: Suit, in rect: CGRect) -> UIBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let path = UIBezierPath()
        switch suit {
        case .hearts:
            path.move(to: p(0.5, 0.94))
            path.addCurve(to: p(0.04, 0.40), controlPoint1: p(0.30, 0.76), controlPoint2: p(0.04, 0.60))
            path.addCurve(to: p(0.5, 0.20), controlPoint1: p(0.04, 0.10), controlPoint2: p(0.40, 0.02))
            path.addCurve(to: p(0.96, 0.40), controlPoint1: p(0.60, 0.02), controlPoint2: p(0.96, 0.10))
            path.addCurve(to: p(0.5, 0.94), controlPoint1: p(0.96, 0.60), controlPoint2: p(0.70, 0.76))
        case .diamonds:
            path.move(to: p(0.5, 0.02))
            path.addQuadCurve(to: p(0.90, 0.5), controlPoint: p(0.70, 0.30))
            path.addQuadCurve(to: p(0.5, 0.98), controlPoint: p(0.70, 0.70))
            path.addQuadCurve(to: p(0.10, 0.5), controlPoint: p(0.30, 0.70))
            path.addQuadCurve(to: p(0.5, 0.02), controlPoint: p(0.30, 0.30))
        case .spades:
            path.move(to: p(0.5, 0.03))
            path.addCurve(to: p(0.95, 0.52), controlPoint1: p(0.70, 0.26), controlPoint2: p(0.95, 0.34))
            path.addCurve(to: p(0.5, 0.70), controlPoint1: p(0.95, 0.80), controlPoint2: p(0.62, 0.86))
            path.addCurve(to: p(0.05, 0.52), controlPoint1: p(0.38, 0.86), controlPoint2: p(0.05, 0.80))
            path.addCurve(to: p(0.5, 0.03), controlPoint1: p(0.05, 0.34), controlPoint2: p(0.30, 0.26))
            path.close()
            path.append(stem(p))
        case .clubs:
            let r = rect.width * 0.205
            for (cx, cy) in [(0.5, 0.26), (0.26, 0.56), (0.74, 0.56)] {
                path.append(UIBezierPath(ovalIn: CGRect(x: p(cx, cy).x - r, y: p(cx, cy).y - r, width: r * 2, height: r * 2)))
            }
            let mid = rect.width * 0.12
            path.append(UIBezierPath(ovalIn: CGRect(x: p(0.5, 0.5).x - mid, y: p(0.5, 0.5).y - mid, width: mid * 2, height: mid * 2)))
            path.append(stem(p))
        }
        path.close()
        return path
    }

    private static func stem(_ p: (CGFloat, CGFloat) -> CGPoint) -> UIBezierPath {
        let stem = UIBezierPath()
        stem.move(to: p(0.5, 0.58))
        stem.addQuadCurve(to: p(0.28, 0.98), controlPoint: p(0.47, 0.92))
        stem.addLine(to: p(0.72, 0.98))
        stem.addQuadCurve(to: p(0.5, 0.58), controlPoint: p(0.53, 0.92))
        stem.close()
        return stem
    }

    // MARK: - Pip-Anordnung

    /// Klassische Positionen (normiert im Pip-Feld; y ≥ 0.5 wird um 180° gedreht gezeichnet).
    static func pipLayout(_ rank: Rank) -> [CGPoint] {
        let l: CGFloat = 0, c: CGFloat = 0.5, r: CGFloat = 1
        switch rank {
        case .two: return [CGPoint(x: c, y: 0), CGPoint(x: c, y: 1)]
        case .three: return [CGPoint(x: c, y: 0), CGPoint(x: c, y: 0.5), CGPoint(x: c, y: 1)]
        case .four: return [CGPoint(x: l, y: 0), CGPoint(x: r, y: 0), CGPoint(x: l, y: 1), CGPoint(x: r, y: 1)]
        case .five: return pipLayout(.four) + [CGPoint(x: c, y: 0.5)]
        case .six: return [CGPoint(x: l, y: 0), CGPoint(x: r, y: 0), CGPoint(x: l, y: 0.5), CGPoint(x: r, y: 0.5),
                           CGPoint(x: l, y: 1), CGPoint(x: r, y: 1)]
        case .seven: return pipLayout(.six) + [CGPoint(x: c, y: 0.25)]
        case .eight: return pipLayout(.six) + [CGPoint(x: c, y: 0.25), CGPoint(x: c, y: 0.75)]
        case .nine:
            return [0, 1.0 / 3, 2.0 / 3, 1].flatMap { y in [CGPoint(x: l, y: y), CGPoint(x: r, y: y)] } + [CGPoint(x: c, y: 0.5)]
        case .ten:
            return [0, 1.0 / 3, 2.0 / 3, 1].flatMap { y in [CGPoint(x: l, y: y), CGPoint(x: r, y: y)] }
                + [CGPoint(x: c, y: 1.0 / 6), CGPoint(x: c, y: 5.0 / 6)]
        case .ace: return [CGPoint(x: c, y: 0.5)]
        case .jack, .queen, .king: return []
        }
    }

    // MARK: - Vorderseite

    static func drawFace(rank: Rank, suit: Suit, in ctx: CGContext) {
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)
        let color = color(for: suit)
        drawPaper(in: ctx, rect: rect)

        // Ecken (oben links und gedreht unten rechts)
        func corner() {
            let label = rank.label
            let font = UIFont(name: "Georgia-Bold", size: label.count > 1 ? 52 : 60) ?? .systemFont(ofSize: 58, weight: .bold)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color,
                                                                       .kern: label.count > 1 ? -4 : 0])
            let ts = text.size()
            let cx: CGFloat = 40
            text.draw(at: CGPoint(x: cx - ts.width / 2, y: 14))
            color.setFill()
            suitPath(suit, in: CGRect(x: cx - 17, y: 82, width: 34, height: 38)).fill()
        }
        corner()
        ctx.saveGState()
        ctx.translateBy(x: w, y: h)
        ctx.rotate(by: .pi)
        corner()
        ctx.restoreGState()

        switch rank {
        case .jack, .queen, .king:
            drawCourt(rank: rank, suit: suit, in: ctx)
        case .ace:
            let s = w * 0.40
            color.setFill()
            let path = suitPath(suit, in: CGRect(x: (w - s) / 2, y: (h - s * 1.12) / 2, width: s, height: s * 1.12))
            path.fill()
            if suit == .spades {
                // Klassisches verziertes Pik-Ass
                UIColor(white: 1, alpha: 0.9).setStroke()
                let inner = suitPath(suit, in: CGRect(x: (w - s) / 2 + s * 0.16, y: (h - s * 1.12) / 2 + s * 0.2, width: s * 0.68, height: s * 0.76))
                inner.lineWidth = 2.5
                inner.stroke()
            }
        default:
            let area = CGRect(x: w * 0.27, y: h * 0.17, width: w * 0.46, height: h * 0.66)
            let pw = w * 0.165, ph = pw * 1.12
            color.setFill()
            for point in pipLayout(rank) {
                let center = CGPoint(x: area.minX + point.x * area.width, y: area.minY + point.y * area.height)
                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                if point.y > 0.5 { ctx.rotate(by: .pi) }
                suitPath(suit, in: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph)).fill()
                ctx.restoreGState()
            }
        }
    }

    /// Papier: leicht warmes Weiß, feiner Verlauf und Rand.
    private static func drawPaper(in ctx: CGContext, rect: CGRect) {
        let shape = UIBezierPath(roundedRect: rect, cornerRadius: 22)
        ctx.saveGState()
        shape.addClip()
        let colors = [UIColor(red: 0.995, green: 0.993, blue: 0.985, alpha: 1).cgColor,
                      UIColor(red: 0.955, green: 0.948, blue: 0.930, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width * 0.4, y: rect.height), options: [])
        // Sehr feine Papierstruktur
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2_200 {
            let x = CGFloat.random(in: 0..<rect.width, using: &rng), y = CGFloat.random(in: 0..<rect.height, using: &rng)
            ctx.setFillColor(UIColor(white: 0.5, alpha: .random(in: 0.015...0.04, using: &rng)).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
        }
        ctx.restoreGState()
        UIColor(white: 0.74, alpha: 1).setStroke()
        let border = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 21)
        border.lineWidth = 2
        border.stroke()
    }

    /// Bildkarte: doppelter Rahmen, gespiegelte Hälften wie bei echten Bildkarten.
    private static func drawCourt(rank: Rank, suit: Suit, in ctx: CGContext) {
        let w = size.width, h = size.height
        let color = color(for: suit)
        let gold = UIColor(red: 0.74, green: 0.58, blue: 0.28, alpha: 1)
        let frame = CGRect(x: w * 0.19, y: h * 0.12, width: w * 0.62, height: h * 0.76)

        // Hintergrund mit feiner Schraffur
        ctx.saveGState()
        UIBezierPath(rect: frame).addClip()
        UIColor(red: 0.985, green: 0.970, blue: 0.935, alpha: 1).setFill()
        ctx.fill(frame)
        ctx.setStrokeColor(color.withAlphaComponent(0.07).cgColor)
        ctx.setLineWidth(1.5)
        var x = frame.minX - frame.height
        while x < frame.maxX {
            ctx.move(to: CGPoint(x: x, y: frame.maxY)); ctx.addLine(to: CGPoint(x: x + frame.height, y: frame.minY))
            x += 9
        }
        ctx.strokePath()
        ctx.restoreGState()

        color.setStroke()
        let outer = UIBezierPath(rect: frame); outer.lineWidth = 3; outer.stroke()
        gold.setStroke()
        let inner = UIBezierPath(rect: frame.insetBy(dx: 6, dy: 6)); inner.lineWidth = 2; inner.stroke()
        // Mittellinie (Spiegelachse)
        color.withAlphaComponent(0.5).setStroke()
        let mid = UIBezierPath()
        mid.move(to: CGPoint(x: frame.minX + 6, y: frame.midY)); mid.addLine(to: CGPoint(x: frame.maxX - 6, y: frame.midY))
        mid.lineWidth = 1.5; mid.stroke()

        func half() {
            // Oberhälfte: Krone/Ornament, großer Buchstabe, Farbsymbol
            let top = frame.minY + 14
            gold.setFill()
            let crown = UIBezierPath()
            let cx = frame.midX, cw = frame.width * 0.34
            crown.move(to: CGPoint(x: cx - cw / 2, y: top + 30))
            crown.addLine(to: CGPoint(x: cx - cw / 2, y: top + 8))
            crown.addLine(to: CGPoint(x: cx - cw / 4, y: top + 20))
            crown.addLine(to: CGPoint(x: cx, y: top))
            crown.addLine(to: CGPoint(x: cx + cw / 4, y: top + 20))
            crown.addLine(to: CGPoint(x: cx + cw / 2, y: top + 8))
            crown.addLine(to: CGPoint(x: cx + cw / 2, y: top + 30))
            crown.close()
            if rank != .jack { crown.fill() }
            let font = UIFont(name: "Georgia-Bold", size: 118) ?? .systemFont(ofSize: 110, weight: .black)
            let letter = NSAttributedString(string: rank.label, attributes: [.font: font, .foregroundColor: color])
            let ls = letter.size()
            letter.draw(at: CGPoint(x: frame.midX - ls.width / 2, y: frame.minY + frame.height * 0.08 + 18))
            color.setFill()
            let s: CGFloat = 40
            suitPath(suit, in: CGRect(x: frame.minX + 18, y: frame.minY + 20, width: s, height: s * 1.1)).fill()
        }
        half()
        ctx.saveGState()
        ctx.translateBy(x: w, y: h)
        ctx.rotate(by: .pi)
        half()
        ctx.restoreGState()
    }

    // MARK: - Rückseite

    static func drawBack(in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        drawPaper(in: ctx, rect: rect)
        let inner = rect.insetBy(dx: 20, dy: 20)
        let path = UIBezierPath(roundedRect: inner, cornerRadius: 12)
        let base = UIColor(red: 0.50, green: 0.05, blue: 0.09, alpha: 1)
        base.setFill()
        path.fill()
        ctx.saveGState()
        path.addClip()
        // Feines Gittermuster wie bei klassischen Kartenrücken
        ctx.setStrokeColor(UIColor(red: 0.85, green: 0.30, blue: 0.32, alpha: 0.55).cgColor)
        ctx.setLineWidth(1.4)
        var x = inner.minX - inner.height
        while x < inner.maxX + inner.height {
            ctx.move(to: CGPoint(x: x, y: inner.minY)); ctx.addLine(to: CGPoint(x: x + inner.height, y: inner.maxY))
            ctx.move(to: CGPoint(x: x + inner.height, y: inner.minY)); ctx.addLine(to: CGPoint(x: x, y: inner.maxY))
            x += 14
        }
        ctx.strokePath()
        ctx.restoreGState()
        UIColor(white: 1, alpha: 0.85).setStroke()
        let line = UIBezierPath(roundedRect: inner.insetBy(dx: 8, dy: 8), cornerRadius: 8)
        line.lineWidth = 2
        line.stroke()
        // Dezentes Medaillon
        let medal = CGRect(x: rect.midX - 54, y: rect.midY - 70, width: 108, height: 140)
        base.setFill()
        UIBezierPath(ovalIn: medal).fill()
        UIColor(white: 1, alpha: 0.85).setStroke()
        let ring = UIBezierPath(ovalIn: medal.insetBy(dx: 5, dy: 5)); ring.lineWidth = 2; ring.stroke()
        let font = UIFont(name: "Georgia-Bold", size: 44) ?? .systemFont(ofSize: 42, weight: .bold)
        let bc = NSAttributedString(string: "BC", attributes: [.font: font, .foregroundColor: UIColor(white: 1, alpha: 0.9)])
        let bs = bc.size()
        bc.draw(at: CGPoint(x: rect.midX - bs.width / 2, y: rect.midY - bs.height / 2))
    }
}
