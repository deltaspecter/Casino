import SceneKit
import UIKit

extension SCNNode {
    /// Führt eine Aktion aus und wartet auf ihr Ende.
    /// Mit Sicherheits-Timeout, damit nichts hängen bleibt, falls die Szene pausiert.
    @MainActor
    func run(_ action: SCNAction, key: String? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ResumeGate(continuation)
            if let key {
                runAction(action, forKey: key) { gate.resume() }
            } else {
                runAction(action) { gate.resume() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + action.duration + 0.75) { gate.resume() }
        }
    }
}

/// Stellt sicher, dass eine Continuation genau einmal fortgesetzt wird.
private final class ResumeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}

@MainActor
func sceneDelay(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
}

enum Materials {
    static func pbr(color: UIColor, roughness: CGFloat = 0.5, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static func textured(_ image: UIImage, roughness: CGFloat = 0.5, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static let gold = pbr(color: Theme.uiGold, roughness: 0.28, metalness: 1)
    static let leather = pbr(color: UIColor(red: 0.06, green: 0.05, blue: 0.05, alpha: 1), roughness: 0.42)
    static let skin = pbr(color: UIColor(red: 0.86, green: 0.67, blue: 0.55, alpha: 1), roughness: 0.62)
}

extension SCNVector3 {
    static func + (l: SCNVector3, r: SCNVector3) -> SCNVector3 { SCNVector3(l.x + r.x, l.y + r.y, l.z + r.z) }
    static func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 { SCNVector3(l.x - r.x, l.y - r.y, l.z - r.z) }
    static func * (l: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(l.x * s, l.y * s, l.z * s) }

    static func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 { a + (b - a) * t }
}
