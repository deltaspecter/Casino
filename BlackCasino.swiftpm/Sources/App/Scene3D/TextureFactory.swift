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

    static let cardPixelSize = CGSize(width: 360, height: 504)

    static func cardFace(rank: Rank, suit: Suit) -> UIImage {
        cached("card-\(rank.rawValue)-\(suit.rawValue)") {
            let size = cardPixelSize
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                let cg = ctx.cgContext
                // Papier mit leichter Struktur
                UIColor(red: 0.985, green: 0.975, blue: 0.955, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 26).fill()
                cg.setStrokeColor(UIColor(white: 0.82, alpha: 1).cgColor)
                cg.setLineWidth(3)
                UIBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 25).stroke()

                let color = suit.isRed ? UIColor(red: 0.80, green: 0.05, blue: 0.12, alpha: 1)
                                       : UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)

                // Ecken
                let rankFont = UIFont.systemFont(ofSize: 74, weight: .heavy)
                let suitFont = UIFont.systemFont(ofSize: 58, weight: .regular)
                func drawCorner() {
                    let rankText = NSAttributedString(string: rank.label, attributes: [.font: rankFont, .foregroundColor: color])
                    let rs = rankText.size()
                    rankText.draw(at: CGPoint(x: 52 - rs.width / 2, y: 14))
                    let suitText = NSAttributedString(string: suit.symbol, attributes: [.font: suitFont, .foregroundColor: color])
                    let ss = suitText.size()
                    suitText.draw(at: CGPoint(x: 52 - ss.width / 2, y: 92))
                }
                drawCorner()
                cg.saveGState()
                cg.translateBy(x: size.width, y: size.height)
                cg.rotate(by: .pi)
                drawCorner()
                cg.restoreGState()

                // Mitte
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                if rank >= .jack && rank <= .king {
                    let frame = rect.insetBy(dx: 92, dy: 120)
                    let path = UIBezierPath(roundedRect: frame, cornerRadius: 14)
                    (suit.isRed ? Theme.uiRed.withAlphaComponent(0.08) : UIColor(white: 0, alpha: 0.05)).setFill()
                    path.fill()
                    Theme.uiGold.setStroke()
                    path.lineWidth = 5
                    path.stroke()
                    let crown = NSAttributedString(string: rank.label, attributes: [
                        .font: UIFont.systemFont(ofSize: 150, weight: .black), .foregroundColor: color])
                    let cs = crown.size()
                    crown.draw(at: CGPoint(x: center.x - cs.width / 2, y: center.y - cs.height / 2 - 30))
                    let s = NSAttributedString(string: suit.symbol, attributes: [
                        .font: UIFont.systemFont(ofSize: 80), .foregroundColor: color])
                    let ssz = s.size()
                    s.draw(at: CGPoint(x: center.x - ssz.width / 2, y: center.y + 50))
                } else {
                    let big = NSAttributedString(string: suit.symbol, attributes: [
                        .font: UIFont.systemFont(ofSize: rank == .ace ? 230 : 190), .foregroundColor: color])
                    let bs = big.size()
                    big.draw(at: CGPoint(x: center.x - bs.width / 2, y: center.y - bs.height / 2))
                    if rank != .ace {
                        let small = NSAttributedString(string: rank.label, attributes: [
                            .font: UIFont.systemFont(ofSize: 60, weight: .bold), .foregroundColor: color.withAlphaComponent(0.85)])
                        let s = small.size()
                        small.draw(at: CGPoint(x: center.x - s.width / 2, y: center.y + bs.height / 2 - 20))
                    }
                }
            }
        }
    }

    static func cardBack() -> UIImage {
        cached("card-back") {
            let size = cardPixelSize
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                let cg = ctx.cgContext
                UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 26).fill()
                let inner = rect.insetBy(dx: 18, dy: 18)
                let innerPath = UIBezierPath(roundedRect: inner, cornerRadius: 16)
                Theme.uiRedDeep.setFill()
                innerPath.fill()
                cg.saveGState()
                innerPath.addClip()
                // Rautenmuster
                cg.setStrokeColor(Theme.uiRed.withAlphaComponent(0.9).cgColor)
                cg.setLineWidth(3)
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    cg.move(to: CGPoint(x: x + size.height, y: 0)); cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += 26
                }
                cg.strokePath()
                cg.restoreGState()
                Theme.uiGold.setStroke()
                innerPath.lineWidth = 4
                innerPath.stroke()
                // Medaillon
                let medal = CGRect(x: size.width / 2 - 78, y: size.height / 2 - 78, width: 156, height: 156)
                UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1).setFill()
                UIBezierPath(ovalIn: medal).fill()
                Theme.uiGold.setStroke()
                let ring = UIBezierPath(ovalIn: medal.insetBy(dx: 4, dy: 4))
                ring.lineWidth = 6
                ring.stroke()
                let bc = NSAttributedString(string: "BC", attributes: [
                    .font: UIFont.systemFont(ofSize: 64, weight: .black), .foregroundColor: Theme.uiGoldLight])
                let bs = bc.size()
                bc.draw(at: CGPoint(x: size.width / 2 - bs.width / 2, y: size.height / 2 - bs.height / 2))
            }
        }
    }

    // MARK: - Chips

    static func chipTop(_ d: ChipDenomination) -> UIImage {
        cached("chip-top-\(d.rawValue)") {
            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                let rect = CGRect(origin: .zero, size: size)
                let c = CGPoint(x: 128, y: 128)
                d.baseColor.setFill()
                cg.fill(rect)
                // Kantenmarkierungen
                d.stripeColor.setFill()
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4
                    cg.saveGState()
                    cg.translateBy(x: c.x, y: c.y)
                    cg.rotate(by: a)
                    cg.fill(CGRect(x: 96, y: -14, width: 34, height: 28))
                    cg.restoreGState()
                }
                // Innenring
                let inner = CGRect(x: 52, y: 52, width: 152, height: 152)
                d.baseColor.withAlphaComponent(1).setFill()
                UIBezierPath(ovalIn: inner).fill()
                let ring = UIBezierPath(ovalIn: inner.insetBy(dx: 4, dy: 4))
                ring.lineWidth = 4
                Theme.uiGoldLight.withAlphaComponent(0.85).setStroke()
                ring.setLineDash([10, 6], count: 2, phase: 0)
                ring.stroke()
                let text = NSAttributedString(string: d.label, attributes: [
                    .font: UIFont.systemFont(ofSize: d.label.count > 3 ? 44 : 58, weight: .black),
                    .foregroundColor: d.textColor])
                let ts = text.size()
                text.draw(at: CGPoint(x: c.x - ts.width / 2, y: c.y - ts.height / 2))
            }
        }
    }

    static func chipEdge(_ d: ChipDenomination) -> UIImage {
        cached("chip-edge-\(d.rawValue)") {
            let size = CGSize(width: 512, height: 32)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                d.baseColor.setFill()
                ctx.cgContext.fill(CGRect(origin: .zero, size: size))
                d.stripeColor.setFill()
                for i in 0..<8 {
                    ctx.cgContext.fill(CGRect(x: CGFloat(i) * 64 + 20, y: 0, width: 24, height: 32))
                }
            }
        }
    }

    // MARK: - Tisch

    enum FeltKind: String { case blackjack, poker }

    /// Filz mit Aufdruck. Außerhalb der Tischform transparent, damit eine einfache Ebene genügt.
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
                // Grundfarbe: tiefes Rot-Schwarz mit Vignette
                let colors = [UIColor(red: 0.36, green: 0.03, blue: 0.06, alpha: 1).cgColor,
                              UIColor(red: 0.12, green: 0.01, blue: 0.03, alpha: 1).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                let center = kind == .blackjack ? CGPoint(x: size.width / 2, y: size.height * 0.35)
                                                : CGPoint(x: size.width / 2, y: size.height / 2)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                      endRadius: size.width * 0.6, options: [.drawsAfterEndLocation])
                // Feine Filzstruktur
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<26_000 {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng)
                    let a = CGFloat.random(in: 0.02...0.06, using: &rng)
                    cg.setFillColor(UIColor(white: Bool.random(using: &rng) ? 1 : 0, alpha: a).cgColor)
                    cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
                switch kind {
                case .blackjack: drawBlackjackPrint(cg, size: size)
                case .poker: drawPokerPrint(cg, size: size)
                }
                cg.restoreGState()
            }
        }
    }

    private static func drawBlackjackPrint(_ cg: CGContext, size: CGSize) {
        let gold = Theme.uiGold
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
        let gold = Theme.uiGold
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
                let palette: [UIColor] = [Theme.uiRed, Theme.uiRedDeep, Theme.uiGold, UIColor(red: 1, green: 0.55, blue: 0.3, alpha: 1)]
                for _ in 0..<70 {
                    let r = CGFloat.random(in: 20...110, using: &rng)
                    let p = CGPoint(x: .random(in: 0...size.width, using: &rng), y: .random(in: size.height * 0.15...size.height * 0.75, using: &rng))
                    let color = palette.randomElement(using: &rng)!
                    let colors = [color.withAlphaComponent(.random(in: 0.15...0.45, using: &rng)).cgColor,
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
