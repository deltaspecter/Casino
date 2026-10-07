import SceneKit
import UIKit

/// Virtueller Dealer.
///
/// Liegt im Bundle eine Datei `Dealer.usdz` (vollständig computergenerierte, frei erfundene Figur
/// mit ARKit-kompatiblen Blendshapes wie `eyeBlinkLeft`, `jawOpen`, `mouthSmileLeft`), wird diese
/// verwendet – inklusive Gesichtsanimation über `SCNMorpher`. Andernfalls baut die App einen
/// stilisierten Dealer aus Grundkörpern, der dieselben Animationen (Atmen, Blinzeln, Kopf-
/// bewegungen, Geben, Nicken, Lächeln) beherrscht.
///
/// Wichtig: Es wird keine reale Person nachgebildet.
@MainActor
final class DealerAvatar {
    enum Reaction { case playerWon, dealerWon, neutral }

    let node = SCNNode()
    private var rig: DealerRig

    private init(rig: DealerRig) {
        self.rig = rig
        node.name = "dealer"
        node.addChildNode(rig.root)
    }

    static func make() -> DealerAvatar {
        if let url = Bundle.main.url(forResource: "Dealer", withExtension: "usdz"),
           let rig = ImportedDealerRig(url: url) {
            return DealerAvatar(rig: rig)
        }
        return DealerAvatar(rig: ProceduralDealerRig())
    }

    func startIdle() { rig.startIdle() }

    /// Gibt eine Karte in Richtung `target` (Weltkoordinaten).
    func dealGesture(toward target: SCNVector3) {
        let local = node.convertPosition(target, from: nil)
        rig.reach(toward: local, rightHand: local.x >= 0)
        rig.look(at: local)
    }

    func look(at target: SCNVector3) {
        rig.look(at: node.convertPosition(target, from: nil))
    }

    func react(_ reaction: Reaction) { rig.react(reaction) }
}

/// Gemeinsame Schnittstelle für importierte und prozedurale Dealer-Modelle.
@MainActor
protocol DealerRig: AnyObject {
    var root: SCNNode { get }
    func startIdle()
    func reach(toward local: SCNVector3, rightHand: Bool)
    func look(at local: SCNVector3)
    func react(_ reaction: DealerAvatar.Reaction)
}

// MARK: - Importiertes Modell (USDZ mit Blendshapes)

@MainActor
final class ImportedDealerRig: DealerRig {
    let root = SCNNode()
    private var morphers: [SCNMorpher] = []
    private var head: SCNNode?

    init?(url: URL) {
        guard let scene = try? SCNScene(url: url, options: [.checkConsistency: true]) else { return nil }
        for child in scene.rootNode.childNodes { root.addChildNode(child) }
        root.enumerateHierarchy { node, _ in
            if let morpher = node.morpher { self.morphers.append(morpher) }
            if self.head == nil, let name = node.name?.lowercased(), name.contains("head") { self.head = node }
        }
    }

    private func setWeight(_ weight: CGFloat, _ target: String, duration: TimeInterval) {
        for morpher in morphers where morpher.targets.contains(where: { $0.name == target }) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            morpher.setWeight(weight, forTargetNamed: target)
            SCNTransaction.commit()
        }
    }

    func startIdle() {
        // Vorhandene Animationen (z. B. „idle“) aus der Datei laufen automatisch weiter.
        scheduleBlink()
    }

    private func scheduleBlink() {
        let wait = Double.random(in: 2.4...5.5) // nur Optik
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, self.root.parent != nil else { return }
            self.setWeight(1, "eyeBlinkLeft", duration: 0.07)
            self.setWeight(1, "eyeBlinkRight", duration: 0.07)
            try? await Task.sleep(for: .milliseconds(120))
            self.setWeight(0, "eyeBlinkLeft", duration: 0.1)
            self.setWeight(0, "eyeBlinkRight", duration: 0.1)
            self.scheduleBlink()
        }
    }

    func reach(toward local: SCNVector3, rightHand: Bool) {
        // Ohne bekannte Skelett-Namen nur ein dezentes Vorbeugen
        let lean = SCNAction.sequence([.rotateBy(x: 0.06, y: 0, z: 0, duration: 0.2), .rotateBy(x: -0.06, y: 0, z: 0, duration: 0.25)])
        root.play(lean)
    }

    func look(at local: SCNVector3) {
        guard let head else { return }
        let yaw = atan2(local.x, local.z) * 0.5
        head.play(.rotateTo(x: CGFloat(head.eulerAngles.x), y: CGFloat(yaw), z: 0, duration: 0.3, usesShortestUnitArc: true))
    }

    func react(_ reaction: DealerAvatar.Reaction) {
        let smile: CGFloat = reaction == .playerWon ? 0.7 : 0.3
        setWeight(smile, "mouthSmileLeft", duration: 0.25)
        setWeight(smile, "mouthSmileRight", duration: 0.25)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            self?.setWeight(0, "mouthSmileLeft", duration: 0.4)
            self?.setWeight(0, "mouthSmileRight", duration: 0.4)
        }
    }
}

// MARK: - Prozeduraler Dealer

@MainActor
final class ProceduralDealerRig: DealerRig {
    let root = SCNNode()
    private let torso = SCNNode()
    private let headPivot = SCNNode()
    private let head = SCNNode()
    private var eyes: [SCNNode] = []
    private let mouth = SCNNode()
    private var brows: [SCNNode] = []
    private let leftShoulder = SCNNode()
    private let rightShoulder = SCNNode()
    private let leftElbow = SCNNode()
    private let rightElbow = SCNNode()

    init() {
        let skin = Materials.skin
        let shirt = Materials.pbr(color: UIColor(white: 0.93, alpha: 1), roughness: 0.7)
        let vest = Materials.pbr(color: UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1), roughness: 0.55)
        let accent = Materials.pbr(color: Theme.uiRed, roughness: 0.4)
        let hair = Materials.pbr(color: UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1), roughness: 0.75)

        // Oberkörper (Hüfte liegt unter Tischhöhe)
        let torsoGeo = SCNCapsule(capRadius: 0.17, height: 0.62)
        torsoGeo.materials = [vest]
        torso.geometry = torsoGeo
        torso.scale = SCNVector3(1, 1, 0.62)
        torso.position = SCNVector3(0, 0.08, 0)
        root.addChildNode(torso)

        // Hemd-Einsatz und Weste mit roten Revers
        let shirtFront = SCNNode(geometry: SCNBox(width: 0.1, height: 0.26, length: 0.02, chamferRadius: 0.01))
        shirtFront.geometry?.materials = [shirt]
        shirtFront.position = SCNVector3(0, 0.22, 0.095)
        root.addChildNode(shirtFront)
        for side: Float in [-1, 1] {
            let lapel = SCNNode(geometry: SCNBox(width: 0.035, height: 0.24, length: 0.012, chamferRadius: 0.006))
            lapel.geometry?.materials = [accent]
            lapel.position = SCNVector3(side * 0.06, 0.21, 0.103)
            lapel.eulerAngles.z = side * 0.28
            root.addChildNode(lapel)
        }
        // Fliege
        for side: Float in [-1, 1] {
            let wing = SCNNode(geometry: SCNPyramid(width: 0.04, height: 0.035, length: 0.015))
            wing.geometry?.materials = [accent]
            wing.position = SCNVector3(side * 0.02, 0.33, 0.11)
            wing.eulerAngles.z = side * (.pi / 2)
            root.addChildNode(wing)
        }
        let knot = SCNNode(geometry: SCNSphere(radius: 0.011))
        knot.geometry?.materials = [accent]
        knot.position = SCNVector3(0, 0.33, 0.115)
        root.addChildNode(knot)

        // Hals & Kopf
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.08))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 0.39, 0)
        root.addChildNode(neck)

        headPivot.position = SCNVector3(0, 0.43, 0)
        root.addChildNode(headPivot)
        let headGeo = SCNSphere(radius: 0.1)
        headGeo.segmentCount = 48
        headGeo.materials = [skin]
        head.geometry = headGeo
        head.scale = SCNVector3(0.92, 1.12, 1)
        head.position = SCNVector3(0, 0.1, 0)
        headPivot.addChildNode(head)

        let hairGeo = SCNSphere(radius: 0.104)
        hairGeo.segmentCount = 48
        hairGeo.materials = [hair]
        let hairNode = SCNNode(geometry: hairGeo)
        hairNode.scale = SCNVector3(0.96, 0.95, 1.0)
        hairNode.position = SCNVector3(0, 0.135, -0.018)
        headPivot.addChildNode(hairNode)

        for side: Float in [-1, 1] {
            let eyeWhite = SCNNode(geometry: SCNSphere(radius: 0.014))
            eyeWhite.geometry?.materials = [Materials.pbr(color: UIColor(white: 0.97, alpha: 1), roughness: 0.2)]
            eyeWhite.position = SCNVector3(side * 0.034, 0.115, 0.083)
            let iris = SCNNode(geometry: SCNSphere(radius: 0.0075))
            iris.geometry?.materials = [Materials.pbr(color: UIColor(red: 0.2, green: 0.12, blue: 0.07, alpha: 1), roughness: 0.15)]
            iris.position = SCNVector3(0, 0, 0.0095)
            eyeWhite.addChildNode(iris)
            headPivot.addChildNode(eyeWhite)
            eyes.append(eyeWhite)

            let brow = SCNNode(geometry: SCNBox(width: 0.036, height: 0.006, length: 0.008, chamferRadius: 0.003))
            brow.geometry?.materials = [hair]
            brow.position = SCNVector3(side * 0.035, 0.143, 0.089)
            brow.eulerAngles.z = side * -0.12
            headPivot.addChildNode(brow)
            brows.append(brow)

            let ear = SCNNode(geometry: SCNSphere(radius: 0.02))
            ear.geometry?.materials = [skin]
            ear.scale = SCNVector3(0.5, 1, 0.8)
            ear.position = SCNVector3(side * 0.093, 0.1, 0)
            headPivot.addChildNode(ear)
        }

        let nose = SCNNode(geometry: SCNCapsule(capRadius: 0.011, height: 0.04))
        nose.geometry?.materials = [skin]
        nose.position = SCNVector3(0, 0.095, 0.1)
        nose.eulerAngles.x = 0.25
        headPivot.addChildNode(nose)

        let lips = SCNCapsule(capRadius: 0.005, height: 0.04)
        lips.materials = [Materials.pbr(color: UIColor(red: 0.62, green: 0.32, blue: 0.3, alpha: 1), roughness: 0.4)]
        mouth.geometry = lips
        mouth.eulerAngles.z = .pi / 2
        mouth.position = SCNVector3(0, 0.055, 0.092)
        headPivot.addChildNode(mouth)

        // Arme: Schulter → Oberarm → Ellbogen → Unterarm → Hand
        for (shoulder, elbow, side) in [(leftShoulder, leftElbow, Float(-1)), (rightShoulder, rightElbow, Float(1))] {
            shoulder.position = SCNVector3(side * 0.2, 0.3, 0)
            root.addChildNode(shoulder)
            let ball = SCNNode(geometry: SCNSphere(radius: 0.065))
            ball.geometry?.materials = [shirt]
            shoulder.addChildNode(ball)
            let upper = SCNNode(geometry: SCNCapsule(capRadius: 0.045, height: 0.26))
            upper.geometry?.materials = [shirt]
            upper.position = SCNVector3(0, -0.12, 0)
            shoulder.addChildNode(upper)
            elbow.position = SCNVector3(0, -0.24, 0)
            shoulder.addChildNode(elbow)
            let fore = SCNNode(geometry: SCNCapsule(capRadius: 0.04, height: 0.24))
            fore.geometry?.materials = [shirt]
            fore.position = SCNVector3(0, -0.11, 0)
            elbow.addChildNode(fore)
            let cuff = SCNNode(geometry: SCNCylinder(radius: 0.042, height: 0.02))
            cuff.geometry?.materials = [Materials.gold]
            cuff.position = SCNVector3(0, -0.215, 0)
            elbow.addChildNode(cuff)
            let hand = SCNNode(geometry: SCNSphere(radius: 0.038))
            hand.geometry?.materials = [skin]
            hand.scale = SCNVector3(0.9, 1.1, 0.6)
            hand.position = SCNVector3(0, -0.255, 0)
            elbow.addChildNode(hand)
            // Ruhehaltung: Unterarme nach vorn auf den Tisch gerichtet
            shoulder.eulerAngles = SCNVector3(-0.35, 0, side * 0.12)
            elbow.eulerAngles = SCNVector3(-1.15, 0, 0)
        }
    }

    func startIdle() {
        // Atmen
        let inhale = SCNAction.scale(to: 1.012, duration: 2.1)
        inhale.timingMode = .easeInEaseOut
        let exhale = SCNAction.scale(to: 1.0, duration: 2.3)
        exhale.timingMode = .easeInEaseOut
        root.play(.repeatForever(.sequence([inhale, exhale])), key: "breath")

        // Leichtes Kopfwiegen
        let swayA = SCNAction.rotateTo(x: 0.03, y: 0.06, z: 0.01, duration: 3.4, usesShortestUnitArc: true)
        swayA.timingMode = .easeInEaseOut
        let swayB = SCNAction.rotateTo(x: -0.01, y: -0.05, z: -0.01, duration: 3.8, usesShortestUnitArc: true)
        swayB.timingMode = .easeInEaseOut
        headPivot.play(.repeatForever(.sequence([swayA, swayB])), key: "sway")

        scheduleBlink()
    }

    private func scheduleBlink() {
        let wait = Double.random(in: 2.2...5.8) // nur Optik
        let close = SCNAction.customAction(duration: 0.07) { node, t in
            node.scale.y = Float(1 - 0.9 * (t / 0.07))
        }
        let open = SCNAction.customAction(duration: 0.1) { node, t in
            node.scale.y = Float(0.1 + 0.9 * (t / 0.1))
        }
        for eye in eyes { eye.play(.sequence([.wait(duration: wait), close, open])) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.2))
            guard let self, self.root.parent != nil else { return }
            self.scheduleBlink()
        }
    }

    func reach(toward local: SCNVector3, rightHand: Bool) {
        let shoulder = rightHand ? rightShoulder : leftShoulder
        let elbow = rightHand ? rightElbow : leftElbow
        let side: Float = rightHand ? 1 : -1
        let yaw = max(-0.6, min(0.6, atan2(local.x - side * 0.2, max(0.2, local.z))))
        let out = SCNAction.rotateTo(x: -1.05, y: CGFloat(yaw), z: CGFloat(side * 0.12), duration: 0.18, usesShortestUnitArc: true)
        out.timingMode = .easeOut
        let back = SCNAction.rotateTo(x: -0.35, y: 0, z: CGFloat(side * 0.12), duration: 0.3, usesShortestUnitArc: true)
        back.timingMode = .easeInEaseOut
        shoulder.play(.sequence([out, back]), key: "reach")
        let extend = SCNAction.rotateTo(x: -0.55, y: 0, z: 0, duration: 0.18, usesShortestUnitArc: true)
        let bend = SCNAction.rotateTo(x: -1.15, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true)
        elbow.play(.sequence([extend, bend]), key: "reach")
    }

    func look(at local: SCNVector3) {
        let yaw = max(-0.5, min(0.5, atan2(local.x, max(0.1, local.z)) * 0.6))
        let pitch = Float(0.18)
        headPivot.removeAction(forKey: "sway")
        let turn = SCNAction.rotateTo(x: CGFloat(pitch), y: CGFloat(yaw), z: 0, duration: 0.25, usesShortestUnitArc: true)
        turn.timingMode = .easeInEaseOut
        let hold = SCNAction.wait(duration: 0.9)
        let reset = SCNAction.rotateTo(x: 0.05, y: 0, z: 0, duration: 0.6, usesShortestUnitArc: true)
        reset.timingMode = .easeInEaseOut
        headPivot.play(.sequence([turn, hold, reset]), key: "look")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard let self, self.headPivot.action(forKey: "look") == nil else { return }
            self.resumeSway()
        }
    }

    private func resumeSway() {
        guard headPivot.action(forKey: "sway") == nil else { return }
        let swayA = SCNAction.rotateTo(x: 0.03, y: 0.06, z: 0.01, duration: 3.4, usesShortestUnitArc: true)
        swayA.timingMode = .easeInEaseOut
        let swayB = SCNAction.rotateTo(x: -0.01, y: -0.05, z: -0.01, duration: 3.8, usesShortestUnitArc: true)
        swayB.timingMode = .easeInEaseOut
        headPivot.play(.repeatForever(.sequence([swayA, swayB])), key: "sway")
    }

    func react(_ reaction: DealerAvatar.Reaction) {
        // Lächeln: Mund breiter, Augenbrauen leicht angehoben; Nicken bei Spielergewinn
        let widen = SCNAction.scale(to: reaction == .playerWon ? 1.35 : 1.15, duration: 0.2)
        let relax = SCNAction.scale(to: 1, duration: 0.5)
        mouth.play(.sequence([widen, .wait(duration: 1.2), relax]))
        for brow in brows {
            brow.play(.sequence([.moveBy(x: 0, y: 0.004, z: 0, duration: 0.2), .wait(duration: 1.0),
                                      .moveBy(x: 0, y: -0.004, z: 0, duration: 0.4)]))
        }
        if reaction == .playerWon {
            let nodDown = SCNAction.rotateBy(x: 0.14, y: 0, z: 0, duration: 0.18)
            let nodUp = SCNAction.rotateBy(x: -0.14, y: 0, z: 0, duration: 0.22)
            head.play(.sequence([nodDown, nodUp, nodDown, nodUp]))
        }
    }
}
