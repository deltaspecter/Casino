import SwiftUI
import SceneKit

/// Bindet eine `CasinoStage` in SwiftUI ein und meldet die Bildschirmpositionen
/// der Anker-Punkte (für Labels wie Handwerte oder Spielernamen).
struct SceneContainer: UIViewRepresentable {
    let stage: CasinoStage
    var onAnchorsProjected: (([String: CGPoint]) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: nil)
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.isJitteringEnabled = false
        view.delegate = context.coordinator
        context.coordinator.onAnchorsProjected = onAnchorsProjected
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onAnchorsProjected = onAnchorsProjected
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.delegate = nil
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var onAnchorsProjected: (([String: CGPoint]) -> Void)?
        private var lastReport: [String: CGPoint] = [:]
        private var lastTime: TimeInterval = 0

        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard onAnchorsProjected != nil, time - lastTime > 0.1 else { return }
            lastTime = time
            // Anker-Knoten im Render-Thread lesen (nur Positionen, keine Mutation)
            let nodes = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("anchor-") == true }
            var result: [String: CGPoint] = [:]
            for node in nodes {
                guard let name = node.name else { continue }
                let p = renderer.projectPoint(node.presentation.worldPosition)
                guard p.z > 0, p.z < 1 else { continue }
                result[String(name.dropFirst("anchor-".count))] = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            }
            guard hasChanged(result) else { return }
            lastReport = result
            let callback = onAnchorsProjected
            DispatchQueue.main.async { callback?(result) }
        }

        private func hasChanged(_ new: [String: CGPoint]) -> Bool {
            guard new.count == lastReport.count else { return true }
            for (key, point) in new {
                guard let old = lastReport[key] else { return true }
                if abs(old.x - point.x) > 0.5 || abs(old.y - point.y) > 0.5 { return true }
            }
            return false
        }
    }
}
