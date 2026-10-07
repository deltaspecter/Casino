import SceneKit
import UIKit

/// Gestapelte 3D-Chips mit realistischen Proportionen (Ø 40 mm, 3,4 mm hoch).
final class ChipStackNode: SCNNode {
    static let radius: CGFloat = 0.02
    static let thickness: CGFloat = 0.0034

    private static var geometryCache: [ChipDenomination: SCNCylinder] = [:]

    @MainActor
    static func geometry(for d: ChipDenomination) -> SCNCylinder {
        if let g = geometryCache[d] { return g }
        let g = SCNCylinder(radius: radius, height: thickness)
        g.radialSegmentCount = 40
        let edge = Materials.textured(TextureFactory.chipEdge(d), roughness: 0.35)
        edge.diffuse.wrapS = .repeat
        let top = Materials.textured(TextureFactory.chipTop(d), roughness: 0.3)
        // Reihenfolge bei SCNCylinder: Mantel, Deckel, Boden
        g.materials = [edge, top, top]
        geometryCache[d] = g
        return g
    }

    private(set) var amount: Int
    private var chipNodes: [SCNNode] = []
    private let maxChips: Int

    @MainActor
    init(amount: Int, maxChips: Int = 20) {
        self.amount = 0
        self.maxChips = maxChips
        super.init()
        if amount > 0 { setAmount(amount) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: Float { Float(chipNodes.count) * Float(Self.thickness) }

    /// Baut den Stapel ohne Animation neu auf.
    @MainActor
    func setAmount(_ newAmount: Int) {
        amount = newAmount
        chipNodes.forEach { $0.removeFromParentNode() }
        chipNodes = []
        for d in ChipDenomination.breakdown(newAmount, maxChips: maxChips) {
            appendChip(d)
        }
    }

    @MainActor
    private func appendChip(_ d: ChipDenomination) {
        let node = SCNNode(geometry: Self.geometry(for: d))
        let index = chipNodes.count
        // Leichte Unregelmäßigkeit wie bei echten, von Hand gestapelten Chips (rein optisch)
        node.position = SCNVector3(Float.random(in: -0.0008...0.0008),
                                   Float(Self.thickness) * (Float(index) + 0.5),
                                   Float.random(in: -0.0008...0.0008))
        node.eulerAngles.y = Float.random(in: 0...(2 * .pi))
        node.castsShadow = true
        addChildNode(node)
        chipNodes.append(node)
    }

    /// Chips fallen einzeln auf den Stapel – mit kleinem Rückprall.
    @MainActor
    func dropIn(amount newAmount: Int) async {
        let before = chipNodes.count
        setAmount(newAmount)
        let newChips = chipNodes.suffix(from: min(before, chipNodes.count))
        for (i, chip) in newChips.enumerated() {
            let rest = chip.position
            chip.position.y += 0.09
            chip.opacity = 0
            let fall = SCNAction.move(to: rest, duration: 0.18)
            fall.timingMode = .easeIn
            let bounceUp = SCNAction.moveBy(x: 0, y: 0.0025, z: 0, duration: 0.05)
            let bounceDown = SCNAction.moveBy(x: 0, y: -0.0025, z: 0, duration: 0.05)
            chip.runAction(.sequence([.wait(duration: Double(i) * 0.035), .fadeIn(duration: 0.02), fall, bounceUp, bounceDown]))
        }
        if !newChips.isEmpty {
            Haptics.chip()
            await sceneDelay(Double(newChips.count) * 0.035 + 0.3)
        }
    }

    /// Ganzen Stapel an eine andere Position schieben (z. B. zum Gewinner).
    @MainActor
    func slide(to target: SCNVector3, duration: TimeInterval = 0.45, fadeOut: Bool = false) async {
        let move = SCNAction.move(to: target, duration: duration)
        move.timingMode = .easeInEaseOut
        if fadeOut {
            await run(.sequence([move, .fadeOut(duration: 0.15)]))
            removeFromParentNode()
        } else {
            await run(move)
        }
    }
}
