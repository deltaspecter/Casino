import SceneKit
import UIKit

/// Gemeinsame 3D-Bühne für alle Tische: Licht, Kamera, Hintergrund, Tisch und Dealer.
@MainActor
final class CasinoStage {
    struct CameraSetup {
        var position: SCNVector3
        var target: SCNVector3
        var fieldOfView: CGFloat
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let tableRoot = SCNNode()
    let kind: TextureFactory.FeltKind
    let dealer: DealerAvatar

    /// Punkte, deren Bildschirmposition für SwiftUI-Overlays benötigt wird.
    private(set) var anchors: [String: SCNNode] = [:]

    init(kind: TextureFactory.FeltKind, camera: CameraSetup, dealerPosition: SCNVector3, reducedEffects: Bool) {
        self.kind = kind
        self.dealer = DealerAvatar.make()
        scene.rootNode.addChildNode(tableRoot)
        buildEnvironment()
        buildLights(reducedEffects: reducedEffects)
        buildCamera(camera, reducedEffects: reducedEffects)
        tableRoot.addChildNode(TableBuilder.makeTable(kind: kind))
        dealer.node.position = dealerPosition
        scene.rootNode.addChildNode(dealer.node)
        dealer.startIdle()
    }

    // MARK: - Anker für Overlays

    func setAnchor(_ name: String, at position: SCNVector3) {
        let node = anchors[name] ?? {
            let n = SCNNode()
            n.name = "anchor-\(name)"
            scene.rootNode.addChildNode(n)
            anchors[name] = n
            return n
        }()
        node.position = position
    }

    func removeAnchor(_ name: String) {
        anchors[name]?.removeFromParentNode()
        anchors[name] = nil
    }

    // MARK: - Aufbau

    private func buildEnvironment() {
        scene.background.contents = UIColor(red: 0.015, green: 0.015, blue: 0.02, alpha: 1)
        // Image-Based Lighting für glaubwürdige Reflexionen auf Chips, Rail und Karten
        scene.lightingEnvironment.contents = TextureFactory.backdrop()
        scene.lightingEnvironment.intensity = 0.7

        // Unscharfe Casino-Lichter hinter dem Dealer
        let backdrop = SCNPlane(width: 14, height: 6)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = TextureFactory.backdrop()
        backdrop.firstMaterial = material
        let backdropNode = SCNNode(geometry: backdrop)
        backdropNode.position = SCNVector3(0, 1.2, -4.5)
        backdropNode.castsShadow = false
        scene.rootNode.addChildNode(backdropNode)

        // Dunkler Boden
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial = Materials.pbr(color: UIColor(red: 0.03, green: 0.02, blue: 0.02, alpha: 1), roughness: 0.9)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.8
        scene.rootNode.addChildNode(floorNode)

        scene.fogStartDistance = 4
        scene.fogEndDistance = 9
        scene.fogColor = UIColor.black
    }

    private func buildLights(reducedEffects: Bool) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 110
        ambient.color = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Hauptlicht: warmer Spot über dem Tisch mit weichen Schatten
        let key = SCNLight()
        key.type = .spot
        key.intensity = 1900
        key.temperature = 4300
        key.spotInnerAngle = 35
        key.spotOuterAngle = 85
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = reducedEffects ? 4 : 16
        key.shadowRadius = 5
        key.shadowMapSize = reducedEffects ? CGSize(width: 1024, height: 1024) : CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.65)
        key.zNear = 0.5
        key.zFar = 6
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.15, 2.6, 0.35)
        keyNode.look(at: SCNVector3(0, 0, -0.1))
        scene.rootNode.addChildNode(keyNode)

        // Warme, gedämpfte Seitenlichter des Saals (keine Neonfarben)
        for x: Float in [-2.2, 2.2] {
            let rim = SCNLight()
            rim.type = .omni
            rim.intensity = 160
            rim.color = UIColor(red: 1, green: 0.72, blue: 0.45, alpha: 1)
            rim.attenuationStartDistance = 0.5
            rim.attenuationEndDistance = 4.5
            let node = SCNNode()
            node.light = rim
            node.position = SCNVector3(x, 0.9, -1.4)
            scene.rootNode.addChildNode(node)
        }

        // Weiches Fülllicht von vorn für Gesicht des Dealers
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 220
        fill.temperature = 5200
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(0, 1.4, 2)
        fillNode.look(at: SCNVector3(0, 0.4, -0.7))
        scene.rootNode.addChildNode(fillNode)
    }

    private func buildCamera(_ setup: CameraSetup, reducedEffects: Bool) {
        let camera = SCNCamera()
        // Sichtfeld an der Breite ausrichten: Der Tisch passt auf jedem iPad-Format vollständig ins Bild.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = setup.fieldOfView
        camera.zNear = 0.05
        camera.zFar = 20
        camera.wantsHDR = true
        camera.exposureOffset = 0.1
        camera.bloomIntensity = reducedEffects ? 0 : 0.12
        camera.bloomThreshold = 1.1
        camera.bloomBlurRadius = 8
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 0.8
        camera.saturation = 1.0
        camera.contrast = 0.05
        if !reducedEffects {
            camera.screenSpaceAmbientOcclusionIntensity = 0.7
            camera.screenSpaceAmbientOcclusionRadius = 0.06
        }
        cameraNode.camera = camera
        cameraNode.position = setup.position
        cameraNode.look(at: setup.target)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Kaum merkliches „Atmen“ der Kamera am Spieltisch (wenige Millimeter, sehr langsam).
    func startSubtleSway(target: SCNVector3) {
        startCameraDrift(radius: 0.012, period: 14, target: target)
    }

    /// Sehr langsame Kamerabewegung – lässt die Szene lebendig wirken (Startbildschirm).
    func startCameraDrift(radius: Float = 0.25, period: TimeInterval = 24, target: SCNVector3) {
        let base = cameraNode.position
        let action = SCNAction.customAction(duration: period) { node, elapsed in
            let t = Float(elapsed / CGFloat(period)) * 2 * .pi
            node.position = SCNVector3(base.x + sin(t) * radius, base.y + sin(t * 2) * 0.03, base.z + cos(t) * radius * 0.3)
            node.look(at: target)
        }
        cameraNode.play(.repeatForever(action))
    }
}

/// Baut die Tischgeometrie (Filz, gepolsterte Rail, Holzkorpus).
@MainActor
enum TableBuilder {
    static let blackjackSize = CGSize(width: 1.9, height: 0.95)
    static let pokerSize = CGSize(width: 2.2, height: 1.2)
    /// Z-Position der geraden Dealer-Kante am Blackjack-Tisch.
    static let blackjackDealerEdgeZ: Float = -0.35

    static func makeTable(kind: TextureFactory.FeltKind) -> SCNNode {
        let root = SCNNode()
        root.name = "table"
        switch kind {
        case .blackjack: buildBlackjack(into: root)
        case .poker: buildPoker(into: root)
        }
        return root
    }

    private static func feltNode(kind: TextureFactory.FeltKind, size: CGSize) -> SCNNode {
        let plane = SCNPlane(width: size.width, height: size.height)
        let m = Materials.textured(TextureFactory.felt(kind), roughness: 0.97)
        m.transparencyMode = .aOne
        // Feine Stoffstruktur, gekachelt über den Filz gelegt
        m.multiply.contents = TextureFactory.feltWeave()
        m.multiply.wrapS = .repeat
        m.multiply.wrapT = .repeat
        m.multiply.contentsTransform = SCNMatrix4MakeScale(Float(size.width) * 9, Float(size.height) * 9, 1)
        m.isDoubleSided = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        return node
    }

    private static func buildBlackjack(into root: SCNNode) {
        let size = blackjackSize
        let rx = size.width / 2, ry = size.height
        let edgeZ = blackjackDealerEdgeZ

        let felt = feltNode(kind: .blackjack, size: size)
        felt.position = SCNVector3(0, 0, edgeZ + Float(size.height) / 2)
        root.addChildNode(felt)

        // Gepolsterte Rail entlang des Bogens
        let rail = UIBezierPath()
        let segments = 96
        for i in 0...segments {
            let a = CGFloat.pi + CGFloat(i) / CGFloat(segments) * .pi
            let p = CGPoint(x: cos(a) * (rx + 0.09), y: sin(a) * (ry + 0.09))
            if i == 0 { rail.move(to: p) } else { rail.addLine(to: p) }
        }
        for i in stride(from: segments, through: 0, by: -1) {
            let a = CGFloat.pi + CGFloat(i) / CGFloat(segments) * .pi
            rail.addLine(to: CGPoint(x: cos(a) * (rx - 0.005), y: sin(a) * (ry - 0.005)))
        }
        rail.close()
        rail.flatness = 0.001
        let railShape = SCNShape(path: rail, extrusionDepth: 0.055)
        railShape.chamferRadius = 0.024
        railShape.chamferMode = .both
        railShape.materials = [Materials.leather]
        let railNode = SCNNode(geometry: railShape)
        railNode.eulerAngles.x = -.pi / 2
        railNode.position = SCNVector3(0, 0.012, edgeZ)
        root.addChildNode(railNode)

        // Goldene Zierleiste unter der Rail
        let trim = SCNShape(path: rail, extrusionDepth: 0.006)
        trim.materials = [Materials.gold]
        let trimNode = SCNNode(geometry: trim)
        trimNode.eulerAngles.x = -.pi / 2
        trimNode.position = SCNVector3(0, -0.018, edgeZ)
        trimNode.scale = SCNVector3(1.004, 1.004, 1)
        root.addChildNode(trimNode)

        // Holzkorpus
        let body = UIBezierPath()
        body.move(to: CGPoint(x: -(rx + 0.09), y: 0))
        for i in 0...segments {
            let a = CGFloat.pi + CGFloat(i) / CGFloat(segments) * .pi
            body.addLine(to: CGPoint(x: cos(a) * (rx + 0.09), y: sin(a) * (ry + 0.09)))
        }
        body.close()
        body.flatness = 0.001
        let bodyShape = SCNShape(path: body, extrusionDepth: 0.14)
        bodyShape.materials = [Materials.textured(TextureFactory.woodGrain(), roughness: 0.55)]
        let bodyNode = SCNNode(geometry: bodyShape)
        bodyNode.eulerAngles.x = -.pi / 2
        bodyNode.position = SCNVector3(0, -0.072, edgeZ)
        root.addChildNode(bodyNode)

        // Dealer-Chiptray und Kartenschlitten als Dekoration
        root.addChildNode(makeChipTray(at: SCNVector3(0, 0.002, edgeZ + 0.06)))
        root.addChildNode(makeShoe(at: SCNVector3(0.62, 0, edgeZ + 0.12)))
        root.addChildNode(makeDiscardTray(at: SCNVector3(-0.62, 0, edgeZ + 0.12)))
    }

    private static func buildPoker(into root: SCNNode) {
        let size = pokerSize
        let felt = feltNode(kind: .poker, size: size)
        root.addChildNode(felt)

        let outer = CGRect(x: -size.width / 2 - 0.1, y: -size.height / 2 - 0.1, width: size.width + 0.2, height: size.height + 0.2)
        let inner = CGRect(x: -size.width / 2 + 0.004, y: -size.height / 2 + 0.004, width: size.width - 0.008, height: size.height - 0.008)
        let ring = UIBezierPath(roundedRect: outer, cornerRadius: outer.height / 2)
        ring.append(UIBezierPath(roundedRect: inner, cornerRadius: inner.height / 2))
        ring.usesEvenOddFillRule = true
        ring.flatness = 0.001
        let railShape = SCNShape(path: ring, extrusionDepth: 0.06)
        railShape.chamferRadius = 0.026
        railShape.chamferMode = .both
        railShape.materials = [Materials.leather]
        let railNode = SCNNode(geometry: railShape)
        railNode.eulerAngles.x = -.pi / 2
        railNode.position.y = 0.014
        root.addChildNode(railNode)

        let bodyPath = UIBezierPath(roundedRect: outer, cornerRadius: outer.height / 2)
        bodyPath.flatness = 0.001
        let bodyShape = SCNShape(path: bodyPath, extrusionDepth: 0.14)
        bodyShape.materials = [Materials.textured(TextureFactory.woodGrain(), roughness: 0.55)]
        let bodyNode = SCNNode(geometry: bodyShape)
        bodyNode.eulerAngles.x = -.pi / 2
        bodyNode.position.y = -0.072
        root.addChildNode(bodyNode)

        let trim = SCNShape(path: bodyPath, extrusionDepth: 0.006)
        trim.materials = [Materials.gold]
        let trimNode = SCNNode(geometry: trim)
        trimNode.eulerAngles.x = -.pi / 2
        trimNode.position.y = -0.02
        trimNode.scale = SCNVector3(1.003, 1.003, 1)
        root.addChildNode(trimNode)
    }

    private static func makeChipTray(at position: SCNVector3) -> SCNNode {
        let tray = SCNNode()
        tray.position = position
        let base = SCNBox(width: 0.5, height: 0.012, length: 0.07, chamferRadius: 0.004)
        base.materials = [Materials.pbr(color: UIColor(white: 0.05, alpha: 1), roughness: 0.3, metalness: 0.4)]
        tray.addChildNode(SCNNode(geometry: base))
        let denominations: [ChipDenomination] = [.fiveThousand, .thousand, .fiveHundred, .hundred, .twentyFive, .five, .one]
        for (i, d) in denominations.enumerated() {
            // Liegende Chip-Rollen im Tray
            let roll = SCNNode()
            for k in 0..<10 {
                let chip = SCNNode(geometry: ChipStackNode.geometry(for: d))
                chip.position = SCNVector3(0, Float(k) * Float(ChipStackNode.thickness), 0)
                roll.addChildNode(chip)
            }
            roll.eulerAngles.x = .pi / 2
            roll.position = SCNVector3(-0.21 + Float(i) * 0.07, 0.024, -0.017)
            tray.addChildNode(roll)
        }
        return tray
    }

    private static func makeShoe(at position: SCNVector3) -> SCNNode {
        let shoe = SCNNode()
        shoe.position = position
        let box = SCNBox(width: 0.11, height: 0.07, length: 0.2, chamferRadius: 0.01)
        box.materials = [Materials.pbr(color: Theme.uiRedDeep, roughness: 0.25, metalness: 0.2)]
        let body = SCNNode(geometry: box)
        body.position.y = 0.035
        body.eulerAngles.y = -0.35
        shoe.addChildNode(body)
        let plate = SCNBox(width: 0.112, height: 0.02, length: 0.02, chamferRadius: 0.004)
        plate.materials = [Materials.gold]
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, 0.02, 0.1)
        body.addChildNode(plateNode)
        return shoe
    }

    private static func makeDiscardTray(at position: SCNVector3) -> SCNNode {
        let tray = SCNNode()
        tray.position = position
        let box = SCNBox(width: 0.1, height: 0.04, length: 0.13, chamferRadius: 0.006)
        box.materials = [Materials.pbr(color: UIColor(white: 0.08, alpha: 1), roughness: 0.2, metalness: 0.3)]
        let node = SCNNode(geometry: box)
        node.position.y = 0.02
        node.eulerAngles.y = 0.35
        tray.addChildNode(node)
        return tray
    }
}
