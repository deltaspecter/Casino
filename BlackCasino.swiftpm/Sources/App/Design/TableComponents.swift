import SwiftUI

// MARK: - Karten (2D)

/// Spielkarte mit derselben Textur wie im 3D-Tisch, mit Schatten und optionaler Perspektive.
struct PlayingCardView: View {
    let card: Card?
    var faceUp = true
    var width: CGFloat = 70

    var body: some View {
        let image: UIImage = {
            if let card, faceUp { return TextureFactory.cardFace(rank: card.rank, suit: card.suit) }
            return TextureFactory.cardBack()
        }()
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(CardArt.size.width / CardArt.size.height, contentMode: .fit)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.06, style: .continuous))
            // Zweistufiger Schatten: Kontaktschatten + weicher Schlagschatten
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.35), radius: width * 0.07, x: width * 0.02, y: width * 0.06)
            .accessibilityLabel(card.map { faceUp ? $0.description : "verdeckte Karte" } ?? "verdeckte Karte")
    }
}

/// Karte, die sich realistisch umdreht, sobald ihr Wert bekannt wird (z. B. Dealer-Hole-Card).
struct FlippableCardView: View {
    let card: Card?
    var width: CGFloat = 70
    @State private var shown: Card?
    @State private var angle: Double = 0

    var body: some View {
        PlayingCardView(card: shown, faceUp: shown != nil, width: width)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .onAppear { shown = card }
            .onChange(of: card) { old, new in
                guard old == nil, new != nil else { shown = new; return }
                withAnimation(.easeIn(duration: 0.15)) { angle = 90 } completion: {
                    shown = new
                    angle = -90
                    withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
                    Haptics.card()
                }
            }
    }
}

/// Austeilen: Karte kommt aus dem Dealer-/Deckbereich, dreht sich leicht und landet.
struct CardDealModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .offset(x: (1 - progress) * 60, y: (1 - progress) * -320)
            .rotationEffect(.degrees((1 - progress) * 24))
            .scaleEffect(0.82 + 0.18 * progress)
            .opacity(progress < 0.02 ? 0 : 1)
    }
}

extension AnyTransition {
    static var cardDeal: AnyTransition {
        .asymmetric(insertion: .modifier(active: CardDealModifier(progress: 0), identity: CardDealModifier(progress: 1)),
                    removal: .opacity.combined(with: .scale(scale: 0.9)))
    }
}

extension Animation {
    /// Schnell und elegant, mit kaum sichtbarem Nachfedern beim Aufsetzen.
    static var cardDeal: Animation { .spring(response: 0.42, dampingFraction: 0.86) }
}

// MARK: - Chips (2D mit Tiefe)

/// Chip-Stapel mit sichtbaren Seitenflächen und Schatten – derselbe Farbcode wie im 3D-Tisch.
struct ChipStackView: View {
    let amount: Int
    var chipWidth: CGFloat = 40
    var maxChips = 10

    var body: some View {
        let chips = ChipDenomination.breakdown(amount, maxChips: maxChips).reversed() as ReversedCollection<[ChipDenomination]>
        let list = Array(chips)
        let thickness = chipWidth * 0.11
        let height = chipWidth * 0.5 + thickness * CGFloat(list.count)
        Canvas { ctx, size in
            let w = chipWidth, h = chipWidth * 0.5
            let base = size.height - h / 2 - 2
            // Weicher Bodenschatten
            var shadow = ctx
            shadow.addFilter(.blur(radius: 3))
            shadow.fill(Path(ellipseIn: CGRect(x: 2, y: base - h / 2 + 4, width: w, height: h)), with: .color(.black.opacity(0.45)))
            for (i, d) in list.enumerated() {
                let y = base - CGFloat(i) * thickness
                let topRect = CGRect(x: 0, y: y - h / 2 - thickness, width: w, height: h)
                let bottomRect = CGRect(x: 0, y: y - h / 2, width: w, height: h)
                let baseColor = Color(uiColor: d.baseColor)
                let stripe = Color(uiColor: d.stripeColor)
                // Seitenfläche
                var side = Path()
                side.addRect(CGRect(x: 0, y: topRect.midY, width: w, height: thickness))
                side.addEllipse(in: bottomRect)
                ctx.fill(side, with: .color(baseColor))
                ctx.fill(Path(ellipseIn: bottomRect), with: .color(.black.opacity(0.25)))
                for k in 0..<3 {
                    let x = w * (0.18 + CGFloat(k) * 0.32)
                    ctx.fill(Path(CGRect(x: x, y: topRect.midY + 1, width: w * 0.1, height: thickness)), with: .color(stripe.opacity(0.9)))
                }
                // Oberseite
                ctx.fill(Path(ellipseIn: topRect), with: .color(baseColor))
                ctx.stroke(Path(ellipseIn: topRect.insetBy(dx: w * 0.08, dy: h * 0.08)),
                           with: .color(stripe.opacity(0.85)), style: StrokeStyle(lineWidth: max(1, w * 0.05), dash: [w * 0.08, w * 0.06]))
                ctx.fill(Path(ellipseIn: topRect.insetBy(dx: w * 0.22, dy: h * 0.22)), with: .color(baseColor))
                ctx.stroke(Path(ellipseIn: topRect), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
            }
        }
        .frame(width: chipWidth + 6, height: height + 6)
        .accessibilityLabel("Chips \(amount)")
    }
}

// MARK: - Filz (2D)

/// Dunkelgrüner Spielfilz mit Stoffstruktur, Vignette und dunklem Rand – für 2D-Tische.
struct FeltSurface: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: geo.size.height * 0.5, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.045, blue: 0.035))
                    .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
                RoundedRectangle(cornerRadius: geo.size.height * 0.5, style: .continuous)
                    .fill(RadialGradient(colors: [Color(red: 0.08, green: 0.36, blue: 0.22), Color(red: 0.03, green: 0.19, blue: 0.11)],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.6))
                    .overlay(
                        Image(uiImage: TextureFactory.feltWeave())
                            .resizable(resizingMode: .tile)
                            .blendMode(.multiply)
                            .opacity(0.9)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: geo.size.height * 0.5, style: .continuous))
                    .padding(16)
                RoundedRectangle(cornerRadius: geo.size.height * 0.5, style: .continuous)
                    .strokeBorder(Color(red: 0.62, green: 0.50, blue: 0.30).opacity(0.45), lineWidth: 1.5)
                    .padding(22)
                // Dezentes Oberlicht
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.35))
                    .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.6)
                    .allowsHitTesting(false)
            }
        }
    }
}
