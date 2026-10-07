import SwiftUI

/// Ladebildschirm: animiertes Logo, wandernde Lichtreflexe, Partikel und echter Ladefortschritt
/// (Texturen für Karten, Chips und Tische werden vorgerendert).
struct LoadingView: View {
    @Environment(AppModel.self) private var model
    @State private var progress: Double = 0
    @State private var status = "Tische werden vorbereitet"
    @State private var logoVisible = false
    @State private var ringRotation = 0.0

    var body: some View {
        ZStack {
            LightSweepBackground()
            ParticleField(count: 70)
                .ignoresSafeArea()

            VStack(spacing: 34) {
                Spacer()
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(AngularGradient(colors: [.clear, Theme.red, Theme.goldLight], center: .center),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 168, height: 168)
                        .rotationEffect(.degrees(ringRotation))
                    ChipIcon(color: Theme.red, size: 120)
                        .overlay(Text("BC").font(.display(30)).foregroundStyle(Theme.goldGradient))
                        .shadow(color: Theme.red.opacity(0.6), radius: 30)
                }
                .scaleEffect(logoVisible ? 1 : 0.7)
                .opacity(logoVisible ? 1 : 0)

                BlackCasinoLogo(size: 64)
                    .opacity(logoVisible ? 1 : 0)
                    .offset(y: logoVisible ? 0 : 20)

                Spacer()

                VStack(spacing: 12) {
                    ProgressBar(value: progress, height: 4,
                                fill: AnyShapeStyle(LinearGradient(colors: [Theme.red, Theme.goldLight],
                                                                   startPoint: .leading, endPoint: .trailing)))
                        .frame(width: 360)
                    Text(status.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.opacity)
                }
                .padding(.bottom, 70)
            }
        }
        .task { await load() }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.15)) { logoVisible = true }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { ringRotation = 360 }
        }
    }

    private func load() async {
        let steps: [(String, @Sendable () -> Void)] = [
            ("Karten werden gemischt", { TextureFactory.preloadCards() }),
            ("Chips werden gezählt", { TextureFactory.preloadChips() }),
            ("Tische werden beleuchtet", { TextureFactory.preloadTables() }),
            ("Automaten werden kalibriert", { _ = SlotInfo.reports })
        ]
        let start = Date()
        for (index, step) in steps.enumerated() {
            withAnimation(.easeInOut(duration: 0.3)) { status = step.0 }
            await Task.detached(priority: .userInitiated) { step.1() }.value
            withAnimation(.easeInOut(duration: 0.5)) { progress = Double(index + 1) / Double(steps.count) }
        }
        // Mindestanzeigedauer, damit die Animation wirken kann
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 2.2 { try? await Task.sleep(for: .seconds(2.2 - elapsed)) }
        withAnimation(.easeInOut(duration: 0.3)) { status = "Willkommen" }
        try? await Task.sleep(for: .milliseconds(350))
        model.phase = .start
    }
}
