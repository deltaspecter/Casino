import SceneKit
import CasinoCore

/// 3D-Darstellung des Blackjack-Tisches. Kennt keine Spielregeln –
/// sie setzt nur um, was die Engine bereits entschieden hat.
@MainActor
final class BlackjackTable {
    enum Layout {
        static let shoe = SCNVector3(0.6, 0.075, -0.2)
        static let discard = SCNVector3(-0.62, 0.06, -0.2)
        static let dealerTray = SCNVector3(0, 0.03, -0.29)
        static let playerEdge = SCNVector3(0, 0.06, 0.75)
        static let dealerRowZ: Float = -0.15
        static let handZ: Float = 0.08
        static let betZ: Float = 0.22
        static let cardLift: Float = 0.0006
    }

    let stage: CasinoStage
    private var handOrder: [Int] = []
    private var playerCards: [Int: [CardNode]] = [:]
    private var dealerCards: [CardNode] = []
    private var betStacks: [Int: ChipStackNode] = [:]

    init(reducedEffects: Bool) {
        stage = CasinoStage(
            kind: .blackjack,
            camera: .init(position: SCNVector3(0, 1.02, 1.02), target: SCNVector3(0, 0.05, -0.12), fieldOfView: 44),
            dealerPosition: SCNVector3(0, -0.02, -0.64),
            reducedEffects: reducedEffects
        )
        stage.setAnchor("dealer", at: SCNVector3(0, 0.0, Layout.dealerRowZ + 0.08))
    }

    // MARK: - Positionen

    private func handCenterX(_ index: Int, of count: Int) -> Float {
        let spacing: Float = count >= 4 ? 0.26 : 0.3
        return (Float(index) - Float(count - 1) / 2) * spacing
    }

    private func cardPosition(handID: Int, cardIndex: Int) -> SCNVector3 {
        let index = handOrder.firstIndex(of: handID) ?? 0
        let x = handCenterX(index, of: max(1, handOrder.count)) - 0.012 + Float(cardIndex) * 0.024
        return SCNVector3(x, Layout.cardLift * Float(cardIndex + 1), Layout.handZ - Float(cardIndex) * 0.014)
    }

    private func betPosition(handID: Int) -> SCNVector3 {
        let index = handOrder.firstIndex(of: handID) ?? 0
        return SCNVector3(handCenterX(index, of: max(1, handOrder.count)), 0.0005, Layout.betZ)
    }

    private func dealerCardPosition(_ index: Int) -> SCNVector3 {
        SCNVector3(-0.035 + Float(index) * 0.07, Layout.cardLift * Float(index + 1), Layout.dealerRowZ)
    }

    private func updateAnchors() {
        for name in stage.anchors.keys where name.hasPrefix("hand-") { stage.removeAnchor(name) }
        for id in handOrder {
            let p = betPosition(handID: id)
            stage.setAnchor("hand-\(id)", at: SCNVector3(p.x, 0, Layout.handZ + 0.075))
        }
    }

    // MARK: - Einsätze

    func placeBet(handID: Int, amount: Int) async {
        if !handOrder.contains(handID) {
            handOrder.append(handID)
            updateAnchors()
        }
        let stack = betStacks[handID] ?? {
            let s = ChipStackNode(amount: 0)
            s.position = betPosition(handID: handID)
            stage.tableRoot.addChildNode(s)
            betStacks[handID] = s
            return s
        }()
        await stack.dropIn(amount: amount)
    }

    func updateBet(handID: Int, amount: Int) async {
        await betStacks[handID]?.dropIn(amount: amount)
    }

    // MARK: - Karten

    private func spawnCard(_ card: Card) -> CardNode {
        let node = CardNode(card: card, faceUp: false)
        node.position = Layout.shoe
        node.eulerAngles.y = -0.35
        stage.tableRoot.addChildNode(node)
        return node
    }

    func dealToPlayer(handID: Int, card: Card, rotated: Bool) async {
        let node = spawnCard(card)
        let index = playerCards[handID, default: []].count
        playerCards[handID, default: []].append(node)
        var target = cardPosition(handID: handID, cardIndex: index)
        if rotated { target.z += 0.01 }
        stage.dealer.dealGesture(toward: target)
        Haptics.card()
        await node.fly(to: target, yaw: rotated ? .pi / 2 : 0, faceUp: true)
    }

    func dealToDealer(card: Card, faceDown: Bool) async {
        let node = spawnCard(card)
        let target = dealerCardPosition(dealerCards.count)
        dealerCards.append(node)
        stage.dealer.dealGesture(toward: target)
        Haptics.card()
        await node.fly(to: target, faceUp: !faceDown, duration: 0.34, arc: 0.04)
    }

    func revealHoleCard() async {
        guard dealerCards.count > 1 else { return }
        stage.dealer.look(at: dealerCards[1].position)
        await dealerCards[1].flip(faceUp: true)
    }

    func split(originalID: Int, newID: Int) async {
        guard let index = handOrder.firstIndex(of: originalID), var cards = playerCards[originalID], cards.count >= 2 else { return }
        handOrder.insert(newID, at: index + 1)
        let moved = cards.removeLast()
        playerCards[originalID] = cards
        playerCards[newID] = [moved]
        updateAnchors()

        // Bestehende Hände und Einsätze neu anordnen
        var moves: [(SCNNode, SCNVector3)] = []
        for id in handOrder {
            for (i, node) in (playerCards[id] ?? []).enumerated() {
                moves.append((node, cardPosition(handID: id, cardIndex: i)))
            }
            if let stack = betStacks[id] { moves.append((stack, betPosition(handID: id))) }
        }
        for (node, target) in moves {
            let action = SCNAction.move(to: target, duration: 0.35)
            action.timingMode = .easeInEaseOut
            node.runAction(action)
        }
        await sceneDelay(0.4)
        if let amount = betStacks[originalID]?.amount {
            await placeBet(handID: newID, amount: amount)
        }
    }

    // MARK: - Abrechnung

    func settle(_ results: [HandResult]) async {
        let anyWin = results.contains { $0.outcome == .win || $0.outcome == .blackjack }
        let anyLoss = results.contains { $0.outcome == .lose || $0.outcome == .bust }
        stage.dealer.react(anyWin ? .playerWon : (anyLoss ? .dealerWon : .neutral))

        for result in results {
            guard let stack = betStacks[result.handID] else { continue }
            switch result.outcome {
            case .win, .blackjack:
                let winnings = result.payout - result.stake
                let payout = ChipStackNode(amount: 0)
                payout.position = Layout.dealerTray
                stage.tableRoot.addChildNode(payout)
                await payout.dropIn(amount: winnings)
                var beside = stack.position
                beside.x += 0.045
                await payout.slide(to: beside, duration: 0.35)
                Haptics.chip()
                await sceneDelay(0.35)
                let toPlayer = SCNVector3(stack.position.x, 0.03, Layout.playerEdge.z)
                async let a: Void = payout.slide(to: toPlayer, duration: 0.5, fadeOut: true)
                async let b: Void = stack.slide(to: toPlayer, duration: 0.5, fadeOut: true)
                _ = await (a, b)
            case .push:
                await stack.slide(to: SCNVector3(stack.position.x, 0.03, Layout.playerEdge.z), duration: 0.5, fadeOut: true)
            case .lose, .bust:
                await stack.slide(to: Layout.dealerTray, duration: 0.45, fadeOut: true)
            }
            betStacks[result.handID] = nil
        }
    }

    /// Räumt alle Karten in den Ablagestapel.
    func clear() async {
        var delay: TimeInterval = 0
        var tasks: [CardNode] = []
        for id in handOrder { tasks.append(contentsOf: playerCards[id] ?? []) }
        tasks.append(contentsOf: dealerCards)
        for node in tasks {
            let d = delay
            Task { await node.collect(to: Layout.discard, delay: d) }
            delay += 0.04
        }
        for stack in betStacks.values { stack.removeFromParentNode() }
        betStacks = [:]
        playerCards = [:]
        dealerCards = []
        handOrder = []
        updateAnchors()
        await sceneDelay(delay + 0.45)
    }
}
