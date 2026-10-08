import SwiftUI

/// Dezente aufsteigende Partikel (Glut/Goldstaub). Rein kosmetisch.
struct ParticleField: View {
    var count = 60
    var colors: [Color] = [Theme.red, Theme.redBright, Theme.gold]
    var speed: Double = 1

    private struct Particle {
        let x: Double, phase: Double, size: Double, drift: Double, colorIndex: Int, life: Double
    }

    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * speed
                for p in particles {
                    let progress = ((t / p.life) + p.phase).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.05 - progress * 1.15)
                    let x = size.width * p.x + sin((t + p.phase * 10) * p.drift) * 24
                    let alpha = sin(progress * .pi) * 0.75
                    let rect = CGRect(x: x, y: y, width: p.size, height: p.size)
                    var ctx = context
                    ctx.opacity = alpha
                    ctx.addFilter(.blur(radius: p.size * 0.35))
                    ctx.fill(Path(ellipseIn: rect), with: .color(colors[p.colorIndex % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard particles.isEmpty else { return }
            // Zufall nur für die Optik
            particles = (0..<count).map { _ in
                Particle(x: .random(in: 0...1), phase: .random(in: 0...1), size: .random(in: 1.5...5),
                         drift: .random(in: 0.2...0.9), colorIndex: .random(in: 0..<colors.count),
                         life: .random(in: 7...16))
            }
        }
    }
}

/// Langsam wandernde Lichtreflexe für Hintergründe.
struct LightSweepBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.red.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 500)
                .frame(width: 1000, height: 1000)
                .offset(x: animate ? 260 : -260, y: animate ? -120 : 80)
                .blur(radius: 40)
            RadialGradient(colors: [Theme.gold.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 400)
                .frame(width: 800, height: 800)
                .offset(x: animate ? -300 : 300, y: animate ? 200 : -100)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}

/// Großer Gewinn-Schriftzug mit Hochzählen.
struct WinCelebration: View {
    let title: String
    let amount: Int
    @State private var shown = 0
    @State private var scale: CGFloat = 0.92

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.display(30))
                .tracking(4)
                .foregroundStyle(Theme.goldGradient)
            Text("+\(ChipFormat.string(shown))")
                .font(.numeric(34, weight: .heavy))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(shown)))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .glassPanel(cornerRadius: 26)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { scale = 1 }
            Task { @MainActor in
                let steps = 30
                for i in 1...steps {
                    try? await Task.sleep(for: .milliseconds(40))
                    withAnimation(.linear(duration: 0.04)) { shown = amount * i / steps }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
