import UIKit

/// Erzeugt alle Texturen prozedural (keine externen Assets nötig) und cached sie.
/// `UIGraphicsImageRenderer` ist threadsicher, daher kann im Ladebildschirm vorgerendert werden.
enum TextureFactory {
    private static let cache = NSCache<NSString, UIImage>()

    private static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let image = cache.object(forKey: key as NSString) { return image }
        let image = make()
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    // MARK: - Vorladen

    static func preloadCards() {
        for suit in Suit.allCases { for rank in Rank.allCases { _ = cardFace(rank: rank, suit: suit) } }
        _ = cardBack()
    }

    static func preloadChips() {
        for d in ChipDenomination.allCases { _ = chipTop(d); _ = chipEdge(d) }
    }

    static func preloadTables() {
        _ = felt(.blackjack)
        _ = felt(.poker)
        _ = backdrop()
        _ = woodGrain()
    }

    // MARK: - Karten

    static let cardPixelSize = CardArt.size

    static func cardFace(rank: Rank, suit: Suit) -> UIImage {
        cached("card-\(rank.rawValue)-\(suit.rawValue)") {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: CardArt.size, format: format).image { ctx in
                CardArt.drawFace(rank: rank, suit: suit, in: ctx.cgContext)
            }
        }
    }

    static func cardBack() -> UIImage {
        cached("card-back") {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: CardArt.size, format: format).image { ctx in
                CardArt.drawBack(in: ctx.cgContext)
            }
        }
    }

    // MARK: - Chips

    /// Chip-Oberseite: Grundfarbe mit sechs Kanten-Inlays, Innenring und Wert – wie ein Clay-Chip.
    static func chipTop(_ d: ChipDenomination) -> UIImage {
        cached("chip-top-\(d.rawValue)") {
            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                let c = CGPoint(x: 128, y: 128)
                d.baseColor.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                // Kanten-Inlays
                d.stripeColor.setFill()
                for i in 0..<6 {
                    cg.saveGState()
                    cg.translateBy(x: c.x, y: c.y)
                    cg.rotate(by: CGFloat(i) * .pi / 3)
                    UIBezierPath(roundedRect: CGRect(x: 100, y: -15, width: 30, height: 30), cornerRadius: 3).fill()
                    cg.restoreGState()
                }
                // Leichte Vertiefung zum Rand hin
                let rim = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor(white: 1, alpha: 0.06).cgColor, UIColor(white: 0, alpha: 0.22).cgColor] as CFArray,
                                     locations: [0.6, 1])!
                cg.drawRadialGradient(rim, startCenter: c, startRadius: 0, endCenter: c, endRadius: 128, options: [])
                // Innenfeld mit Ring
                let inner = CGRect(x: 58, y: 58, width: 140, height: 140)
                d.baseColor.setFill()
                UIBezierPath(ovalIn: inner).fill()
                let ring = UIBezierPath(ovalIn: inner.insetBy(dx: 3, dy: 3))
                ring.lineWidth = 3
                d.stripeColor.withAlphaComponent(0.85).setStroke()
                ring.stroke()
                let dashes = UIBezierPath(ovalIn: inner.insetBy(dx: 11, dy: 11))
                dashes.lineWidth = 2
                dashes.setLineDash([3, 5], count: 2, phase: 0)
                d.stripeColor.withAlphaComponent(0.45).setStroke()
                dashes.stroke()
                let font = UIFont(name: "Georgia-Bold", size: d.label.count > 2 ? 46 : 58) ?? .systemFont(ofSize: 52, weight: .heavy)
                let text = NSAttributedString(string: d.label, attributes: [.font: font, .foregroundColor: d.textColor])
                let ts = text.size()
                text.draw(at: CGPoint(x: c.x - ts.width / 2, y: c.y - ts.height / 2))
                // Feine Materialkörnung
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<1_500 {
                    cg.setFillColor(UIColor(white: Bool.random(using: &rng) ? 1 : 0, alpha: 0.05).cgColor)
                    cg.fill(CGRect(x: .random(in: 0..<256, using: &rng), y: .random(in: 0..<256, using: &rng), width: 1.5, height: 1.5))
                }
            }
        }
    }

    /// Chip-Seitenfläche: Grundfarbe mit hellen Kanteneinlagen und dunkleren Rändern oben/unten.
    static func chipEdge(_ d: ChipDenomination) -> UIImage {
        cached("chip-edge-\(d.rawValue)") {
            let size = CGSize(width: 512, height: 32)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                d.baseColor.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                d.stripeColor.setFill()
                for i in 0..<6 {
                    cg.fill(CGRect(x: CGFloat(i) * (512 / 6) + 28, y: 0, width: 30, height: 32))
                }
                let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor(white: 0, alpha: 0.3).cgColor, UIColor(white: 0, alpha: 0).cgColor,
                                                UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.35).cgColor] as CFArray,
                                       locations: [0, 0.25, 0.75, 1])!
                cg.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: 32), options: [])
            }
        }
    }

    // MARK: - Tisch

    enum FeltKind: String { case blackjack, poker }

    /// Dunkelgrüner Filz mit dezentem Aufdruck. Außerhalb der Tischform transparent.
    /// Die feine Stoffstruktur kommt zusätzlich als gekachelte Textur (`feltWeave`).
    static func felt(_ kind: FeltKind) -> UIImage {
        cached("felt-\(kind.rawValue)") {
            let size = CGSize(width: 2048, height: 1024)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                let shape = TableShape.feltPath(kind: kind, in: CGRect(origin: .zero, size: size))
                cg.saveGState()
                shape.addClip()
                let colors = [UIColor(red: 0.07, green: 0.33, blue: 0.20, alpha: 1).cgColor,
                              UIColor(red: 0.03, green: 0.20, blue: 0.12, alpha: 1).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                let center = kind == .blackjack ? CGPoint(x: size.width / 2, y: size.height * 0.45)
                                                : CGPoint(x: size.width / 2, y: size.height / 2)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                      endRadius: size.width * 0.62, options: [.drawsAfterEndLocation])
                switch kind {
                case .blackjack: drawBlackjackPrint(cg, size: size)
                case .poker: drawPokerPrint(cg, size: size)
                }
                cg.restoreGState()
            }
        }
    }

    /// Kachelbare Stoffstruktur (wird über den Filz multipliziert).
    static func feltWeave() -> UIImage {
        cached("felt-weave") {
            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                UIColor(white: 0.93, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                var rng = SystemRandomNumberGenerator()
                // Feine Fasern in zwei Richtungen
                for _ in 0..<5_000 {
                    let x = CGFloat.random(in: 0..<256, using: &rng), y = CGFloat.random(in: 0..<256, using: &rng)
                    let horizontal = Bool.random(using: &rng)
                    cg.setFillColor(UIColor(white: .random(in: 0.78...1.0, using: &rng), alpha: 1).cgColor)
                    cg.fill(horizontal ? CGRect(x: x, y: y, width: .random(in: 2...5, using: &rng), height: 1)
                                       : CGRect(x: x, y: y, width: 1, height: .random(in: 2...5, using: &rng)))
                }
            }
        }
    }

    private static let printColor = UIColor(red: 0.93, green: 0.87, blue: 0.70, alpha: 1)

    private static func drawBlackjackPrint(_ cg: CGContext, size: CGSize) {
        let gold = printColor.withAlphaComponent(0.8)
        // Bogenlinien
        cg.setStrokeColor(gold.withAlphaComponent(0.75).cgColor)
        cg.setLineWidth(5)
        let center = CGPoint(x: size.width / 2, y: 0)
        cg.addArc(center: center, radius: size.height * 0.62, startAngle: 0.18, endAngle: .pi - 0.18, clockwise: false)
        cg.strokePath()
        cg.setLineWidth(3)
        cg.addArc(center: center, radius: size.height * 0.48, startAngle: 0.26, endAngle: .pi - 0.26, clockwise: false)
        cg.strokePath()

        drawArcText("BLACKJACK PAYS 3 TO 2", in: cg, center: center, radius: size.height * 0.555,
                    font: UIFont.systemFont(ofSize: 52, weight: .heavy), color: gold)
        drawArcText("DEALER STANDS ON ALL 17s", in: cg, center: center, radius: size.height * 0.43,
                    font: UIFont.systemFont(ofSize: 34, weight: .bold), color: gold.withAlphaComponent(0.85))
        drawArcText("VIRTUAL CHIPS · NO CASH VALUE", in: cg, center: center, radius: size.height * 0.36,
                    font: UIFont.systemFont(ofSize: 24, weight: .semibold), color: UIColor(white: 1, alpha: 0.35))

        // Einsatzfelder (drei Boxen – für bis zu vier Split-Hände genügt die mittlere Reihe)
        cg.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
        cg.setLineWidth(4)
        for i in 0..<3 {
            let angle = CGFloat.pi / 2 + CGFloat(i - 1) * 0.42
            let r = size.height * 0.80
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            cg.strokeEllipse(in: CGRect(x: p.x - 62, y: p.y - 62, width: 124, height: 124))
        }
        // Logo nahe Dealer
        let logo = NSAttributedString(string: "BLACKCASINO", attributes: [
            .font: UIFont.systemFont(ofSize: 40, weight: .black), .foregroundColor: gold.withAlphaComponent(0.45),
            .kern: 10])
        let ls = logo.size()
        logo.draw(at: CGPoint(x: size.width / 2 - ls.width / 2, y: 60))
    }

    private static func drawPokerPrint(_ cg: CGContext, size: CGSize) {
        let gold = printColor.withAlphaComponent(0.8)
        let inner = CGRect(x: size.width * 0.17, y: size.height * 0.2, width: size.width * 0.66, height: size.height * 0.6)
        let line = UIBezierPath(roundedRect: inner, cornerRadius: inner.height / 2)
        cg.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
        cg.setLineWidth(4)
        cg.addPath(line.cgPath)
        cg.strokePath()
        let logo = NSAttributedString(string: "BLACKCASINO", attributes: [
            .font: UIFont.systemFont(ofSize: 64, weight: .black), .foregroundColor: gold.withAlphaComponent(0.28), .kern: 16])
        let ls = logo.size()
        logo.draw(at: CGPoint(x: size.width / 2 - ls.width / 2, y: size.height * 0.62))
        let sub = NSAttributedString(string: "TEXAS HOLD'EM · VIRTUAL CHIPS ONLY", attributes: [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor(white: 1, alpha: 0.25), .kern: 4])
        let ss = sub.size()
        sub.draw(at: CGPoint(x: size.width / 2 - ss.width / 2, y: size.height * 0.62 + ls.height + 6))
    }

    /// Zeichnet Text entlang eines Kreisbogens (unterer Halbkreis um `center`).
    private static func drawArcText(_ text: String, in cg: CGContext, center: CGPoint, radius: CGFloat,
                                    font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let widths = text.map { NSAttributedString(string: String($0), attributes: attrs).size().width + 4 }
        let totalAngle = widths.reduce(0, +) / radius
        var angle = CGFloat.pi / 2 + totalAngle / 2
        for (char, width) in zip(text, widths) {
            let charAngle = width / radius
            angle -= charAngle / 2
            cg.saveGState()
            cg.translateBy(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            cg.rotate(by: angle - .pi / 2)
            let s = NSAttributedString(string: String(char), attributes: attrs)
            let sz = s.size()
            s.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
            cg.restoreGState()
            angle -= charAngle / 2
        }
    }

    /// Hintergrund mit unscharfen Casino-Lichtern (Bokeh).
    static func backdrop() -> UIImage {
        cached("backdrop") {
            let size = CGSize(width: 2048, height: 1024)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                UIColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                var rng = SystemRandomNumberGenerator()
                // Warme, gedämpfte Lichter eines Spielsaals (kein Neon)
                let palette: [UIColor] = [UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1), UIColor(red: 0.9, green: 0.6, blue: 0.35, alpha: 1),
                                          Theme.uiGold, UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1)]
                for _ in 0..<70 {
                    let r = CGFloat.random(in: 20...110, using: &rng)
                    let p = CGPoint(x: .random(in: 0...size.width, using: &rng), y: .random(in: size.height * 0.15...size.height * 0.75, using: &rng))
                    let color = palette.randomElement(using: &rng)!
                    let colors = [color.withAlphaComponent(.random(in: 0.06...0.22, using: &rng)).cgColor,
                                  color.withAlphaComponent(0).cgColor] as CFArray
                    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                    cg.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
                }
                // Abdunklung nach unten
                let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor.clear.cgColor, UIColor.black.cgColor] as CFArray, locations: [0.4, 1])!
                cg.drawLinearGradient(shade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    static func woodGrain() -> UIImage {
        cached("wood") {
            let size = CGSize(width: 512, height: 512)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                UIColor(red: 0.13, green: 0.06, blue: 0.04, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                var rng = SystemRandomNumberGenerator()
                for i in 0..<140 {
                    let y = CGFloat(i) * 3.7 + .random(in: -2...2, using: &rng)
                    cg.setStrokeColor(UIColor(red: 0.22, green: 0.10, blue: 0.06, alpha: .random(in: 0.2...0.6, using: &rng)).cgColor)
                    cg.setLineWidth(.random(in: 0.5...2.5, using: &rng))
                    cg.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x < size.width {
                        x += 32
                        cg.addLine(to: CGPoint(x: x, y: y + sin(x / 60 + CGFloat(i)) * 3))
                    }
                    cg.strokePath()
                }
            }
        }
    }
}

/// Chip-Werte mit klassischen Farben.
enum ChipDenomination: Int, CaseIterable {
    case one = 1, five = 5, twentyFive = 25, hundred = 100, fiveHundred = 500, thousand = 1_000, fiveThousand = 5_000

    var label: String {
        switch self {
        case .thousand: return "1K"
        case .fiveThousand: return "5K"
        default: return "\(rawValue)"
        }
    }

    var baseColor: UIColor {
        switch self {
        case .one: return UIColor(white: 0.92, alpha: 1)
        case .five: return UIColor(red: 0.80, green: 0.06, blue: 0.13, alpha: 1)
        case .twentyFive: return UIColor(red: 0.08, green: 0.45, blue: 0.25, alpha: 1)
        case .hundred: return UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        case .fiveHundred: return UIColor(red: 0.38, green: 0.14, blue: 0.55, alpha: 1)
        case .thousand: return UIColor(red: 0.85, green: 0.68, blue: 0.30, alpha: 1)
        case .fiveThousand: return UIColor(red: 0.45, green: 0.02, blue: 0.08, alpha: 1)
        }
    }

    var stripeColor: UIColor {
        switch self {
        case .one: return Theme.uiRed
        case .thousand: return UIColor(white: 0.1, alpha: 1)
        case .fiveThousand: return Theme.uiGoldLight
        default: return UIColor(white: 0.96, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .one, .thousand: return UIColor(white: 0.08, alpha: 1)
        default: return .white
        }
    }

    /// Zerlegt einen Betrag in Chips (größte zuerst), begrenzt auf `maxChips` für die Darstellung.
    static func breakdown(_ amount: Int, maxChips: Int = 24) -> [ChipDenomination] {
        var rest = amount
        var result: [ChipDenomination] = []
        for d in allCases.reversed() where rest > 0 {
            while rest >= d.rawValue && result.count < maxChips {
                result.append(d)
                rest -= d.rawValue
            }
        }
        return result
    }
}

/// Umrisse der Tische (geteilt zwischen Textur und Geometrie).
enum TableShape {
    /// Blackjack: Halbellipse, gerade Kante oben (Dealer). Poker: Stadion-Oval.
    static func feltPath(kind: TextureFactory.FeltKind, in rect: CGRect) -> UIBezierPath {
        switch kind {
        case .blackjack:
            // Untere Hälfte einer Ellipse, deren Mittelpunkt auf der oberen Kante liegt.
            // Die obere Hälfte fällt außerhalb des Texturrechtecks und wird so automatisch abgeschnitten.
            return UIBezierPath(ovalIn: CGRect(x: rect.minX, y: rect.minY - rect.height,
                                               width: rect.width, height: rect.height * 2))
        case .poker:
            return UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: rect.height / 2)
        }
    }
}
