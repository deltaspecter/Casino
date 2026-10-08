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

/// Stilisierte, hochwertige Dealer-Figur mit realistischen Proportionen (Kopf ≈ 1/7,5 der
/// Körpergröße). Bewusst ohne gezeichnete Gesichtszüge – wie eine elegante Schneiderpuppe –,
/// damit sie weder cartoonhaft wirkt noch einer realen Person ähnelt.
@MainActor
final class ProceduralDealerRig: DealerRig {
    let root = SCNNode()
    private let chest = SCNNode()
    private let headPivot = SCNNode()
    private let leftShoulder = SCNNode()
    private let rightShoulder = SCNNode()
    private let leftElbow = SCNNode()
    private let rightElbow = SCNNode()

    init() {
        let skin = Materials.pbr(color: UIColor(red: 0.80, green: 0.64, blue: 0.54, alpha: 1), roughness: 0.58)
        let shirt = Materials.pbr(color: UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1), roughness: 0.8)
        let vest = Materials.pbr(color: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1), roughness: 0.62)
        let tie = Materials.pbr(color: UIColor(red: 0.42, green: 0.04, blue: 0.08, alpha: 1), roughness: 0.4)
        let hair = Materials.pbr(color: UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1), roughness: 0.7)
        let metal = Materials.pbr(color: UIColor(red: 0.62, green: 0.55, blue: 0.42, alpha: 1), roughness: 0.3, metalness: 1)

        // Oberkörper: Brustkorb leicht verjüngt (Hüfte liegt unter der Tischkante)
        chest.position = SCNVector3(0, 0.12, 0)
        root.addChildNode(chest)
        let torso = SCNNode(geometry: SCNBox(width: 0.40, height: 0.50, length: 0.22, chamferRadius: 0.085))
        torso.geometry?.materials = [shirt]
        chest.addChildNode(torso)
        let waist = SCNNode(geometry: SCNBox(width: 0.34, height: 0.22, length: 0.20, chamferRadius: 0.07))
        waist.geometry?.materials = [vest]
        waist.position = SCNVector3(0, -0.22, 0)
        chest.addChildNode(waist)
        // Weste: zwei Vorderteile mit V-Ausschnitt
        for side: Float in [-1, 1] {
            let panel = SCNNode(geometry: SCNBox(width: 0.17, height: 0.40, length: 0.012, chamferRadius: 0.006))
            panel.geometry?.materials = [vest]
            panel.position = SCNVector3(side * 0.105, -0.04, 0.107)
            panel.eulerAngles.z = side * -0.10
            chest.addChildNode(panel)
            let back = SCNNode(geometry: SCNBox(width: 0.19, height: 0.46, length: 0.012, chamferRadius: 0.006))
            back.geometry?.materials = [vest]
            back.position = SCNVector3(side * 0.10, 0, -0.106)
            chest.addChildNode(back)
            // Westenknöpfe
            if side < 0 {
                for i in 0..<3 {
                    let button = SCNNode(geometry: SCNSphere(radius: 0.006))
                    button.geometry?.materials = [metal]
                    button.position = SCNVector3(-0.012, -0.16 + Float(i) * 0.06, 0.116)
                    chest.addChildNode(button)
                }
            }
        }
        // Krawatte und Kragen
        let knot = SCNNode(geometry: SCNBox(width: 0.028, height: 0.03, length: 0.02, chamferRadius: 0.008))
        knot.geometry?.materials = [tie]
        knot.position = SCNVector3(0, 0.21, 0.112)
        chest.addChildNode(knot)
        let tieBlade = SCNNode(geometry: SCNPyramid(width: 0.04, height: 0.16, length: 0.01))
        tieBlade.geometry?.materials = [tie]
        tieBlade.eulerAngles.z = .pi
        tieBlade.position = SCNVector3(0, 0.19, 0.112)
        chest.addChildNode(tieBlade)
        let collar = SCNNode(geometry: SCNTube(innerRadius: 0.043, outerRadius: 0.052, height: 0.04))
        collar.geometry?.materials = [shirt]
        collar.position = SCNVector3(0, 0.26, 0.004)
        chest.addChildNode(collar)

        // Hals und Kopf (gesichtslos, natürlich proportioniert)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.042, height: 0.09))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 0.40, 0)
        root.addChildNode(neck)
        headPivot.position = SCNVector3(0, 0.44, 0)
        root.addChildNode(headPivot)
        let head = SCNNode(geometry: SCNSphere(radius: 0.095))
        (head.geometry as? SCNSphere)?.segmentCount = 64
        head.geometry?.materials = [skin]
        head.scale = SCNVector3(0.82, 1.08, 0.94)
        head.position = SCNVector3(0, 0.1, 0)
        headPivot.addChildNode(head)
        let jaw = SCNNode(geometry: SCNSphere(radius: 0.07))
        (jaw.geometry as? SCNSphere)?.segmentCount = 48
        jaw.geometry?.materials = [skin]
        jaw.scale = SCNVector3(0.92, 0.85, 0.95)
        jaw.position = SCNVector3(0, 0.05, 0.018)
        headPivot.addChildNode(jaw)
        let nose = SCNNode(geometry: SCNPyramid(width: 0.022, height: 0.045, length: 0.02))
        nose.geometry?.materials = [skin]
        nose.position = SCNVector3(0, 0.082, 0.086)
        nose.eulerAngles.x = -0.2
        headPivot.addChildNode(nose)
        for side: Float in [-1, 1] {
            let ear = SCNNode(geometry: SCNSphere(radius: 0.018))
            ear.geometry?.materials = [skin]
            ear.scale = SCNVector3(0.45, 1.1, 0.8)
            ear.position = SCNVector3(side * 0.079, 0.1, -0.005)
            headPivot.addChildNode(ear)
        }
        // Kurzer, gepflegter Haarschnitt
        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.098))
        (hairCap.geometry as? SCNSphere)?.segmentCount = 64
        hairCap.geometry?.materials = [hair]
        hairCap.scale = SCNVector3(0.84, 0.86, 0.96)
        hairCap.position = SCNVector3(0, 0.135, -0.012)
        headPivot.addChildNode(hairCap)

        // Arme: Schulter → Oberarm → Ellbogen → Unterarm → Hand (Hemdsärmel, Ärmelhalter)
        for (shoulder, elbow, side) in [(leftShoulder, leftElbow, Float(-1)), (rightShoulder, rightElbow, Float(1))] {
            shoulder.position = SCNVector3(side * 0.20, 0.33, 0)
            root.addChildNode(shoulder)
            let cap = SCNNode(geometry: SCNSphere(radius: 0.055))
            cap.geometry?.materials = [shirt]
            shoulder.addChildNode(cap)
            let upper = SCNNode(geometry: SCNCapsule(capRadius: 0.042, height: 0.28))
            upper.geometry?.materials = [shirt]
            upper.position = SCNVector3(0, -0.13, 0)
            shoulder.addChildNode(upper)
            let garter = SCNNode(geometry: SCNTorus(ringRadius: 0.043, pipeRadius: 0.005))
            garter.geometry?.materials = [vest]
            garter.position = SCNVector3(0, -0.10, 0)
            shoulder.addChildNode(garter)
            elbow.position = SCNVector3(0, -0.26, 0)
            shoulder.addChildNode(elbow)
            let fore = SCNNode(geometry: SCNCapsule(capRadius: 0.036, height: 0.25))
            fore.geometry?.materials = [shirt]
            fore.position = SCNVector3(0, -0.115, 0)
            elbow.addChildNode(fore)
            let cuff = SCNNode(geometry: SCNCylinder(radius: 0.037, height: 0.025))
            cuff.geometry?.materials = [shirt]
            cuff.position = SCNVector3(0, -0.225, 0)
            elbow.addChildNode(cuff)
            let link = SCNNode(geometry: SCNSphere(radius: 0.006))
            link.geometry?.materials = [metal]
            link.position = SCNVector3(side * -0.035, -0.225, 0.01)
            elbow.addChildNode(link)
            let hand = SCNNode(geometry: SCNBox(width: 0.075, height: 0.09, length: 0.028, chamferRadius: 0.013))
            hand.geometry?.materials = [skin]
            hand.position = SCNVector3(0, -0.285, 0)
            elbow.addChildNode(hand)
            let thumb = SCNNode(geometry: SCNCapsule(capRadius: 0.011, height: 0.05))
            thumb.geometry?.materials = [skin]
            thumb.position = SCNVector3(side * -0.04, -0.27, 0.008)
            thumb.eulerAngles.z = side * 0.5
            elbow.addChildNode(thumb)
            // Ruhehaltung: Unterarme ruhen vorn über dem Tisch
            shoulder.eulerAngles = SCNVector3(-0.32, 0, side * 0.10)
            elbow.eulerAngles = SCNVector3(-1.2, 0, 0)
        }
    }

    func startIdle() {
        // Ruhige Atmung (Brustkorb) – kaum sichtbar
        let inhale = SCNAction.scale(to: 1.008, duration: 2.4)
        inhale.timingMode = .easeInEaseOut
        let exhale = SCNAction.scale(to: 1.0, duration: 2.6)
        exhale.timingMode = .easeInEaseOut
        chest.play(.repeatForever(.sequence([inhale, exhale])), key: "breath")
        resumeSway()
    }

    func reach(toward local: SCNVector3, rightHand: Bool) {
        let shoulder = rightHand ? rightShoulder : leftShoulder
        let elbow = rightHand ? rightElbow : leftElbow
        let side: Float = rightHand ? 1 : -1
        let yaw = max(-0.55, min(0.55, atan2(local.x - side * 0.2, max(0.2, local.z))))
        let out = SCNAction.rotateTo(x: -0.95, y: CGFloat(yaw), z: CGFloat(side * 0.10), duration: 0.2, usesShortestUnitArc: true)
        out.timingMode = .easeOut
        let back = SCNAction.rotateTo(x: -0.32, y: 0, z: CGFloat(side * 0.10), duration: 0.34, usesShortestUnitArc: true)
        back.timingMode = .easeInEaseOut
        shoulder.play(.sequence([out, back]), key: "reach")
        let extend = SCNAction.rotateTo(x: -0.6, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: true)
        extend.timingMode = .easeOut
        let bend = SCNAction.rotateTo(x: -1.2, y: 0, z: 0, duration: 0.34, usesShortestUnitArc: true)
        bend.timingMode = .easeInEaseOut
        elbow.play(.sequence([extend, bend]), key: "reach")
    }

    func look(at local: SCNVector3) {
        let yaw = max(-0.4, min(0.4, atan2(local.x, max(0.1, local.z)) * 0.5))
        headPivot.removeAction(forKey: "sway")
        let turn = SCNAction.rotateTo(x: 0.16, y: CGFloat(yaw), z: 0, duration: 0.35, usesShortestUnitArc: true)
        turn.timingMode = .easeInEaseOut
        let reset = SCNAction.rotateTo(x: 0.06, y: 0, z: 0, duration: 0.7, usesShortestUnitArc: true)
        reset.timingMode = .easeInEaseOut
        headPivot.play(.sequence([turn, .wait(duration: 0.8), reset]), key: "look")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard let self, self.headPivot.action(forKey: "look") == nil else { return }
            self.resumeSway()
        }
    }

    private func resumeSway() {
        guard headPivot.action(forKey: "sway") == nil else { return }
        let a = SCNAction.rotateTo(x: 0.07, y: 0.035, z: 0.006, duration: 4.2, usesShortestUnitArc: true)
        a.timingMode = .easeInEaseOut
        let b = SCNAction.rotateTo(x: 0.05, y: -0.03, z: -0.006, duration: 4.6, usesShortestUnitArc: true)
        b.timingMode = .easeInEaseOut
        headPivot.play(.repeatForever(.sequence([a, b])), key: "sway")
    }

    func react(_ reaction: DealerAvatar.Reaction) {
        // Dezentes, professionelles Nicken – keine übertriebenen Gesten
        guard reaction == .playerWon else { return }
        let down = SCNAction.rotateBy(x: 0.09, y: 0, z: 0, duration: 0.22)
        down.timingMode = .easeInEaseOut
        let up = SCNAction.rotateBy(x: -0.09, y: 0, z: 0, duration: 0.3)
        up.timingMode = .easeInEaseOut
        headPivot.play(.sequence([down, up]), key: "nod")
    }
}
