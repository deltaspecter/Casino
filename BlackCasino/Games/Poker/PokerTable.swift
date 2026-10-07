import SceneKit
import UIKit
import CasinoCore

/// 3D-Darstellung des Poker-Tisches (Oval, bis zu 5 Spieler + Dealer).
@MainActor
final class PokerTable {
    static let cardScale: Float = 1.55
    static let chipScale: Float = 1.35

    let stage: CasinoStage
    private let rx: Float = 1.1
    private let rz: Float = 0.6
    private var seatAngles: [Int: Float] = [:]
    private var holeCards: [Int: [CardNode]] = [:]
    private var communityCards: [CardNode] = []
    private var betStacks: [Int: ChipStackNode] = [:]
    private var potStack: ChipStackNode?
    private let buttonDisc = SCNNode()

    private let deckPosition = SCNVector3(0.32, 0.06, -0.42)
    private let muckPosition = SCNVector3(-0.32, 0.05, -0.42)
    private let potPosition = SCNVector3(0, 0.0005, 0.14)

    init(reducedEffects: Bool) {
        stage = CasinoStage(
            kind: .poker,
            camera: .init(position: SCNVector3(0, 1.62, 1.38), target: SCNVector3(0, -0.02, 0.02), fieldOfView: 46),
            dealerPosition: SCNVector3(0, -0.05, -0.78),
            reducedEffects: reducedEffects
        )
        let disc = SCNCylinder(radius: 0.03, height: 0.008)
        let top = Materials.textured(Self.dealerButtonTexture(), roughness: 0.3)
        disc.materials = [Materials.gold, top, top]
        buttonDisc.geometry = disc
        buttonDisc.opacity = 0
        stage.tableRoot.addChildNode(buttonDisc)
        stage.setAnchor("pot", at: SCNVector3(potPosition.x, 0, potPosition.z + 0.08))
    }

    private static func dealerButtonTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let text = NSAttributedString(string: "D", attributes: [
                .font: UIFont.systemFont(ofSize: 76, weight: .black), .foregroundColor: UIColor(white: 0.08, alpha: 1)])
            let ts = text.size()
            text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2))
        }
    }

    // MARK: - Sitzplätze

    /// Winkel (Grad) der Sitze; 90° = Spieler vorne, 270° = Dealer hinten.
    static func angles(forOpponents count: Int) -> [Float] {
        switch count {
        case 1: return [90, 270 - 70]
        case 2: return [90, 165, 15]
        case 3: return [90, 160, 230, 310]
        default: return [90, 150, 210, 330, 30]
        }
    }

    func configureSeats(ids: [Int], opponents: Int) {
        let angles = Self.angles(forOpponents: opponents)
        seatAngles = [:]
        for (i, id) in ids.enumerated() where i < angles.count {
            seatAngles[id] = angles[i] * .pi / 180
            let label = point(forSeat: id, radius: id == ids.first ? 0.98 : 1.12)
            stage.setAnchor("seat-\(id)", at: label)
        }
    }

    private func point(forSeat id: Int, radius: Float, y: Float = 0) -> SCNVector3 {
        let a = seatAngles[id] ?? .pi / 2
        return SCNVector3(cos(a) * rx * radius, y, sin(a) * rz * radius)
    }

    private func cardPosition(seat id: Int, index: Int, isHuman: Bool) -> SCNVector3 {
        let base = point(forSeat: id, radius: isHuman ? 0.62 : 0.74, y: 0.0006 * Float(index + 1))
        let a = seatAngles[id] ?? .pi / 2
        // Karten tangential nebeneinander
        let tangent = SCNVector3(-sin(a), 0, cos(a) * rz / rx)
        let spread: Float = isHuman ? 0.058 : 0.04
        return base + tangent * ((Float(index) - 0.5) * spread * Self.cardScale / 1.2)
    }

    private func cardYaw(seat id: Int) -> Float {
        let a = seatAngles[id] ?? .pi / 2
        return -(a - .pi / 2)
    }

    private func betPosition(seat id: Int) -> SCNVector3 {
        point(forSeat: id, radius: 0.45, y: 0.0005)
    }

    // MARK: - Hand-Ablauf

    func moveButton(to seat: Int) {
        let target = point(forSeat: seat, radius: 0.6, y: 0.004) + SCNVector3(0.09, 0, 0)
        if buttonDisc.opacity == 0 {
            buttonDisc.position = target
            buttonDisc.play(.fadeIn(duration: 0.3))
        } else {
            let move = SCNAction.move(to: target, duration: 0.45)
            move.timingMode = .easeInEaseOut
            buttonDisc.play(move)
        }
    }

    func dealHoleCard(_ card: Card, seat: Int, index: Int, isHuman: Bool) async {
        let node = CardNode(card: card, faceUp: false, scale: Self.cardScale)
        node.position = deckPosition
        stage.tableRoot.addChildNode(node)
        holeCards[seat, default: []].append(node)
        let target = cardPosition(seat: seat, index: index, isHuman: isHuman)
        stage.dealer.dealGesture(toward: target)
        Haptics.card()
        await node.fly(to: target, yaw: cardYaw(seat: seat), faceUp: isHuman, duration: 0.3, arc: 0.06)
    }

    func dealCommunity(_ cards: [Card], startingAt start: Int) async {
        for (offset, card) in cards.enumerated() {
            let i = start + offset
            let node = CardNode(card: card, faceUp: false, scale: Self.cardScale)
            node.position = deckPosition
            stage.tableRoot.addChildNode(node)
            communityCards.append(node)
            let x = (Float(i) - 2) * 0.064 * Self.cardScale * 1.1
            let target = SCNVector3(x, 0.0006, -0.1)
            stage.dealer.dealGesture(toward: target)
            Haptics.card()
            await node.fly(to: target, faceUp: false, duration: 0.3, arc: 0.04)
        }
        // Gemeinsam umdrehen wirkt wie am echten Tisch
        await flipTogether(Array(communityCards.suffix(cards.count)))
    }

    func setBet(seat: Int, amount: Int) async {
        guard amount > 0 else { return }
        let stack = betStacks[seat] ?? {
            let s = ChipStackNode(amount: 0, maxChips: 14)
            s.scale = SCNVector3(Self.chipScale, Self.chipScale, Self.chipScale)
            s.position = betPosition(seat: seat)
            stage.tableRoot.addChildNode(s)
            betStacks[seat] = s
            return s
        }()
        await stack.dropIn(amount: amount)
    }

    func collectBets(potTotal: Int) async {
        guard !betStacks.isEmpty else { return }
        let stacks = Array(betStacks.values)
        betStacks = [:]
        for stack in stacks.dropLast() {
            Task { await stack.slide(to: potPosition, duration: 0.4, fadeOut: true) }
        }
        if let last = stacks.last {
            await last.slide(to: potPosition, duration: 0.4, fadeOut: true)
        }
        if potStack == nil {
            let pot = ChipStackNode(amount: 0, maxChips: 30)
            pot.scale = SCNVector3(Self.chipScale, Self.chipScale, Self.chipScale)
            pot.position = potPosition
            stage.tableRoot.addChildNode(pot)
            potStack = pot
        }
        potStack?.setAmount(potTotal)
        Haptics.chip()
    }

    func fold(seat: Int) async {
        guard let cards = holeCards[seat] else { return }
        holeCards[seat] = nil
        for (i, node) in cards.enumerated() {
            Task { await node.collect(to: muckPosition, delay: Double(i) * 0.05) }
        }
        await sceneDelay(0.3)
    }

    func reveal(seat: Int) async {
        await flipTogether(holeCards[seat] ?? [])
    }

    private func flipTogether(_ nodes: [CardNode]) async {
        for node in nodes.dropLast() {
            Task { await node.flip(faceUp: true) }
        }
        if let last = nodes.last { await last.flip(faceUp: true) }
    }

    func awardPot(to seat: Int, amount: Int, isLast: Bool) async {
        let target = point(forSeat: seat, radius: 0.85, y: 0.01)
        let stack = ChipStackNode(amount: amount, maxChips: 20)
        stack.scale = SCNVector3(Self.chipScale, Self.chipScale, Self.chipScale)
        stack.position = potPosition
        stage.tableRoot.addChildNode(stack)
        if isLast {
            potStack?.removeFromParentNode()
            potStack = nil
        }
        stage.dealer.look(at: target)
        await stack.slide(to: target, duration: 0.6, fadeOut: true)
        Haptics.chip()
    }

    func clear() async {
        var all: [CardNode] = communityCards
        for cards in holeCards.values { all.append(contentsOf: cards) }
        for (i, node) in all.enumerated() {
            Task { await node.collect(to: muckPosition, delay: Double(i) * 0.02) }
        }
        holeCards = [:]
        communityCards = []
        for stack in betStacks.values { stack.removeFromParentNode() }
        betStacks = [:]
        potStack?.removeFromParentNode()
        potStack = nil
        await sceneDelay(Double(all.count) * 0.02 + 0.45)
    }
}
