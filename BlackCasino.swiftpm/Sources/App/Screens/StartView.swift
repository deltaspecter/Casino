import SwiftUI
import SceneKit

/// Startbildschirm: dunkler Spieltisch in 3D mit roten Lichtern, langsam schwebende Kamera.
struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var stage: CasinoStage?
    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let stage {
                SceneContainer(stage: stage)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
            }

            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            ParticleField(count: 40, speed: 0.6)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer().frame(height: 70)
                BlackCasinoLogo(size: 84)
                    .padding(.horizontal, 40)
                Text("PLAY  •  WIN  •  HAVE FUN")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.goldLight)
                    .opacity(appeared ? 1 : 0)
                Spacer()

                Button {
                    Haptics.thud()
                    model.launchFinished()
                    model.phase = .lobby
                } label: {
                    Text("SPIELEN")
                        .frame(width: 280)
                }
                .buttonStyle(.casino(.primary, size: .large))
                .scaleEffect(pulse ? 1.03 : 1)
                .shadow(color: Theme.red.opacity(pulse ? 0.7 : 0.3), radius: pulse ? 34 : 16)

                NoCashValueNote()
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                    .padding(.horizontal, 40)
            }
            .offset(y: appeared ? 0 : 24)
            .opacity(appeared ? 1 : 0)
        }
        .background(Color.black)
        .onAppear {
            if stage == nil { stage = Self.makeStage(reducedEffects: model.profile.settings.reducedMotion) }
            withAnimation(.easeOut(duration: 1.2)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    @MainActor
    private static func makeStage(reducedEffects: Bool) -> CasinoStage {
        let stage = CasinoStage(
            kind: .blackjack,
            camera: .init(position: SCNVector3(0, 0.62, 1.15), target: SCNVector3(0, 0.12, -0.2), fieldOfView: 40),
            dealerPosition: SCNVector3(0, -0.02, -0.64),
            reducedEffects: reducedEffects
        )
        // Dekoration: ein Blackjack und Chip-Stapel
        let ace = CardNode(card: Card(.ace, .spades), faceUp: true)
        ace.position = SCNVector3(-0.03, 0.0006, 0.1)
        ace.eulerAngles.y = 0.12
        let king = CardNode(card: Card(.king, .hearts), faceUp: true)
        king.position = SCNVector3(0.012, 0.0012, 0.09)
        king.eulerAngles.y = -0.08
        stage.tableRoot.addChildNode(ace)
        stage.tableRoot.addChildNode(king)
        for (i, amount) in [6_250, 1_500, 525].enumerated() {
            let stack = ChipStackNode(amount: amount)
            stack.position = SCNVector3(0.16 + Float(i) * 0.05, 0.0005, 0.16 - Float(i % 2) * 0.03)
            stage.tableRoot.addChildNode(stack)
        }
        stage.startCameraDrift(radius: 0.22, period: 28, target: SCNVector3(0, 0.12, -0.2))
        return stage
    }
}
