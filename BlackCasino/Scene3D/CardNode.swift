import SceneKit
import CasinoCore

/// 3D-Spielkarte aus zwei abgerundeten Flächen (Vorder- und Rückseite).
/// Ruhezustand: flach auf dem Tisch. Umdrehen = Rotation um die Längsachse (Z).
final class CardNode: SCNNode {
    static let width: CGFloat = 0.064
    static let height: CGFloat = 0.089

    let card: Card
    private(set) var isFaceUp: Bool

    init(card: Card, faceUp: Bool, scale: Float = 1) {
        self.card = card
        self.isFaceUp = faceUp
        super.init()
        name = "card-\(card.id)"

        let holder = SCNNode()
        holder.eulerAngles.x = -.pi / 2

        let frontPlane = SCNPlane(width: Self.width, height: Self.height)
        frontPlane.cornerRadius = 0.0045
        frontPlane.firstMaterial = Materials.textured(TextureFactory.cardFace(rank: card.rank, suit: card.suit), roughness: 0.42)
        let front = SCNNode(geometry: frontPlane)

        let backPlane = SCNPlane(width: Self.width, height: Self.height)
        backPlane.cornerRadius = 0.0045
        backPlane.firstMaterial = Materials.textured(TextureFactory.cardBack(), roughness: 0.38)
        let back = SCNNode(geometry: backPlane)
        back.eulerAngles.y = .pi
        back.position.z = -0.0003

        holder.addChildNode(front)
        holder.addChildNode(back)
        addChildNode(holder)

        self.scale = SCNVector3(scale, scale, scale)
        eulerAngles.z = faceUp ? 0 : .pi
        castsShadow = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Bogenförmiger Flug vom Schlitten an die Zielposition – mit Drehung beim Landen.
    @MainActor
    func fly(to target: SCNVector3, yaw: Float = 0, faceUp: Bool, duration: TimeInterval = 0.42, arc: Float = 0.07) async {
        isFaceUp = faceUp
        let mid = SCNVector3.lerp(position, target, 0.5) + SCNVector3(0, arc, 0)
        let up = SCNAction.move(to: mid, duration: duration * 0.45)
        up.timingMode = .easeOut
        let down = SCNAction.move(to: target, duration: duration * 0.55)
        down.timingMode = .easeIn
        let rotate = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: faceUp ? 0 : .pi, duration: duration, usesShortestUnitArc: true)
        rotate.timingMode = .easeInEaseOut
        // Kleiner „Rutscher“ nach dem Aufsetzen wie bei echtem Karton auf Filz
        let slide = SCNAction.move(by: SCNVector3(0, 0, 0.004), duration: 0.08)
        slide.timingMode = .easeOut
        await run(.sequence([.group([.sequence([up, down]), rotate]), slide]))
    }

    /// Umdrehen an Ort und Stelle (anheben, drehen, ablegen).
    @MainActor
    func flip(faceUp: Bool, duration: TimeInterval = 0.38) async {
        guard faceUp != isFaceUp else { return }
        isFaceUp = faceUp
        let lift = SCNAction.moveBy(x: 0, y: 0.03, z: 0, duration: duration / 2)
        lift.timingMode = .easeOut
        let drop = SCNAction.moveBy(x: 0, y: -0.03, z: 0, duration: duration / 2)
        drop.timingMode = .easeIn
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(eulerAngles.y), z: faceUp ? 0 : .pi, duration: duration,
                                      usesShortestUnitArc: false)
        turn.timingMode = .easeInEaseOut
        await run(.group([.sequence([lift, drop]), turn]))
    }

    /// Karte vom Tisch einsammeln und ausblenden.
    @MainActor
    func collect(to target: SCNVector3, delay: TimeInterval = 0) async {
        let move = SCNAction.move(to: target, duration: 0.4)
        move.timingMode = .easeInEaseOut
        let turn = SCNAction.rotateTo(x: 0, y: 0, z: .pi, duration: 0.4, usesShortestUnitArc: true)
        await run(.sequence([.wait(duration: delay), .group([move, turn]), .fadeOut(duration: 0.15)]))
        removeFromParentNode()
    }
}
