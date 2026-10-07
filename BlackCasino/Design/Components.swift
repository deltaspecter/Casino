import SwiftUI

// MARK: - Buttons

struct CasinoButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, gold, ghost }
    enum Size {
        case small, medium, large
        var height: CGFloat { self == .small ? 44 : self == .medium ? 56 : 68 }
        var font: Font { self == .small ? .system(size: 15, weight: .bold) : self == .medium ? .system(size: 18, weight: .heavy) : .system(size: 22, weight: .black) }
    }

    var kind: Kind = .primary
    var size: Size = .medium
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .tracking(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 18 : 28)
            .frame(minHeight: size.height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: size.height / 2.6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size.height / 2.6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: Theme.redGradient
        case .gold: Theme.goldGradient
        case .secondary: Theme.surfaceGradient
        case .ghost: Color.white.opacity(0.04)
        }
    }

    private var foreground: Color {
        kind == .gold ? Color.black.opacity(0.85) : .white
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.white.opacity(0.18)
        case .gold: return Theme.goldLight.opacity(0.6)
        case .secondary, .ghost: return Theme.stroke
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return Theme.red.opacity(isEnabled ? 0.45 : 0)
        case .gold: return Theme.gold.opacity(isEnabled ? 0.35 : 0)
        case .secondary, .ghost: return .black.opacity(0.4)
        }
    }
}

extension ButtonStyle where Self == CasinoButtonStyle {
    static func casino(_ kind: CasinoButtonStyle.Kind = .primary, size: CasinoButtonStyle.Size = .medium,
                       fullWidth: Bool = false) -> CasinoButtonStyle {
        CasinoButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// Runder Icon-Button (Zurück, Info, Einstellungen).
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(systemName))
    }
}

// MARK: - Panels

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerMedium
    var tint: Color = .black

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.45)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = Theme.cornerMedium, tint: Color = .black) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Chips & Kontostand

/// Gezeichnetes Chip-Symbol (kein Bild-Asset nötig).
struct ChipIcon: View {
    var color: Color = Theme.red
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle()
                .strokeBorder(Color.white.opacity(0.92),
                              style: StrokeStyle(lineWidth: size * 0.16, dash: [size * 0.2, size * 0.2]))
                .padding(size * 0.04)
            Circle().fill(color.opacity(0.9)).padding(size * 0.26)
            Circle().strokeBorder(Theme.goldLight.opacity(0.8), lineWidth: max(1, size * 0.04)).padding(size * 0.26)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

struct ChipBalanceView: View {
    let amount: Int
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            ChipIcon(size: compact ? 20 : 26)
            Text(ChipFormat.string(amount))
                .font(.numeric(compact ? 17 : 22, weight: .heavy))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(amount)))
                .animation(.snappy, value: amount)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, compact ? 6 : 9)
        .glassPanel(cornerRadius: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kontostand \(ChipFormat.string(amount)) virtuelle Chips")
    }
}

/// Deutlicher Hinweis: Chips sind rein virtuell.
struct NoCashValueNote: View {
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(compact ? "Virtuelle Chips · kein Echtgeldwert"
                         : "Reines Unterhaltungsspiel · Virtuelle Chips ohne realen Geldwert · Keine Käufe, keine Auszahlungen")
        }
        .font(.system(size: compact ? 11 : 13, weight: .medium))
        .foregroundStyle(Theme.textTertiary)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Logo

struct BlackCasinoLogo: View {
    var size: CGFloat = 64
    var shimmer = true
    @State private var sweep: CGFloat = -1

    var body: some View {
        HStack(spacing: size * 0.08) {
            Text("BLACK")
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
            Text("CASINO")
                .foregroundStyle(Theme.redGradient)
        }
        .font(.display(size))
        .tracking(size * 0.06)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .overlay {
            if shimmer {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Theme.goldLight.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: sweep * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .mask {
                    HStack(spacing: size * 0.08) { Text("BLACK"); Text("CASINO") }
                        .font(.display(size)).tracking(size * 0.06).lineLimit(1).minimumScaleFactor(0.4)
                }
                .allowsHitTesting(false)
            }
        }
        .shadow(color: Theme.red.opacity(0.35), radius: size * 0.3)
        .onAppear {
            guard shimmer else { return }
            withAnimation(.easeInOut(duration: 3.2).delay(0.6).repeatForever(autoreverses: false)) {
                sweep = 1.3
            }
        }
        .accessibilityLabel("BlackCasino")
    }
}

// MARK: - Toasts

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    var tint: Color = Theme.gold
}

struct ToastStack: View {
    let toasts: [Toast]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(toasts) { toast in
                HStack(spacing: 14) {
                    Image(systemName: toast.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(toast.tint)
                        .frame(width: 44, height: 44)
                        .background(toast.tint.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        if let subtitle = toast.subtitle {
                            Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: 440)
                .glassPanel(cornerRadius: 22)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: toasts)
        .padding(.top, 16)
    }
}

// MARK: - Sonstiges

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.display(15, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.gold)
            if let subtitle {
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 8
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.redGradient)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}
