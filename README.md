# BlackCasino

**PLAY • WIN • HAVE FUN** – ein hochwertiges, rein virtuelles Casino-Spiel für das iPad.

> BlackCasino ist ausschließlich ein Unterhaltungsspiel. Alle Chips sind virtuell und haben **keinen realen Geldwert**.
> Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen, keine Kryptowährungen, keine Lootboxen und keinen Umtausch in Geld oder Sachwerte.

## Inhalt

| Bereich | Umfang |
|---|---|
| **Blackjack** | 3D-Tisch, virtueller Dealer, 6-Deck-Schlitten, Hit / Stand / Double / Split (bis 4 Hände), S17, Blackjack 3:2 |
| **Poker** | No-Limit Texas Hold'em gegen 1–4 KI-Gegner mit vier Spielstilen, Side-Pots, drei Tischstufen |
| **Slots** | 3 Automaten (Crimson Sevens, Midnight Gems, Dragon Fortune), 5×3 Walzen, 10 Gewinnlinien, Wild & Scatter |
| **Fortschritt** | Startkapital 10.000 Chips, Login-Serie (7 Tage), Daily Reward, 3 Tagesmissionen, 11 Erfolge, Level mit Aufstiegsbelohnung, einmalige Tutorial-Boni, Startpaket bei leerem Konto |

## Technologie – und warum

**SwiftUI + SceneKit, iPadOS 17+, Swift**

* **SwiftUI** liefert native, flüssige iPad-Oberflächen mit Materialien, Animationen und Touch-Verhalten, die sich wie eine echte Premium-App anfühlen – nicht wie eine Webseite.
* **SceneKit** rendert die Tische mit physikbasierten Materialien (PBR), HDR, Bloom, Vignette, Ambient Occlusion, weichen Schatten und Image-Based Lighting – Metal-beschleunigt und sehr effizient auf iPad-GPUs. Es unterstützt USDZ-Modelle mit Skelett- und Blendshape-Animation (`SCNMorpher`) für den Dealer. Die 3D-Schicht ist gekapselt (`Scene3D/`), sodass ein späterer Umstieg auf RealityKit nur diese Schicht betrifft.
* **Swift Package `CasinoCore`** enthält die komplette Spiellogik ohne UI-Abhängigkeit. Sie ist dadurch isoliert testbar (auch auf Linux/CI) und klar von der Darstellung getrennt.

## Architektur

```
BlackCasino/
├── project.yml                  XcodeGen-Projektdefinition
├── Packages/CasinoCore/         Reine Spiellogik (Swift Package, 31 Unit-Tests)
│   ├── Random/                  Zufallsquelle (CSPRNG) + Fisher-Yates
│   ├── Cards/                   Karten, Deck, Schlitten (Shoe)
│   ├── Blackjack/               Regel-Engine, Handbewertung
│   ├── Poker/                   Hold'em-Engine, Handbewertung, faire KI
│   ├── Slots/                   Automat, Katalog, exakte RTP-Berechnung
│   ├── Progression/             Profil, Wallet, Missionen, Erfolge, Level
│   └── Persistence/             JSON-Speicherung (atomar, mit Korruptions-Recovery)
└── BlackCasino/                 iPad-App
    ├── App/                     App-Einstieg, AppModel (Zustand, Chips, Speichern), Navigation
    ├── Design/                  Design-System (Farben, Typografie, Buttons, Effekte, Haptik)
    ├── Scene3D/                 SceneKit-Bühne, Tisch, Karten, Chips, Dealer, Texturen
    ├── Screens/                 Laden, Start, Hauptmenü, Belohnungen, Profil, Tutorials
    └── Games/
        ├── Blackjack/           ViewModel, 3D-Tisch-Controller, Oberfläche
        ├── Poker/               ViewModel (KI-Ablauf), 3D-Tisch-Controller, Oberfläche
        └── Slots/               Lobby, Automat, Walzen-Animation, Gewinnplan
```

Datenfluss pro Spiel: **Engine** (entscheidet nach Regeln) → **Events** → **ViewModel** (verbucht Chips, spielt Events ab) → **3D-Controller / SwiftUI** (zeigt nur an).
Die Darstellung kann Ergebnisse nicht beeinflussen.

## Zufall & Fairness

* Einzige Zufallsquelle im Spiel: `SystemRandomSource` → `SystemRandomNumberGenerator` (kryptografisch sicherer Systemgenerator).
* Karten werden mit **Fisher-Yates** gemischt (jede Permutation gleich wahrscheinlich); Blackjack nutzt einen 6-Deck-Schlitten mit Neumischen nach 75 %.
* Slots: Jede Walze stoppt an einer **unabhängig, gleichverteilt** gezogenen Position ihres festen Streifens. Kein Zustand zwischen Drehungen, keine Near-Miss-Logik, keine Abhängigkeit vom Kontostand.
* Die theoretische Auszahlungsquote (RTP) wird **exakt** aus Streifen und Gewinntabelle berechnet und im Spiel angezeigt (Crimson Sevens 95,1 %, Midnight Gems 94,2 %, Dragon Fortune 94,9 %). Unit-Tests bestätigen sie zusätzlich per Simulation.
* Poker-KI sieht nur ihre eigenen Karten und das Board (`PokerAIContext`) und schätzt ihre Chancen per Monte-Carlo-Simulation über unbekannte Karten.
* Ergebnisse werden **vor** der Animation berechnet und verbucht. Chips auf dem Tisch liegen auf einem Treuhand-Konto und werden nach einem App-Abbruch beim nächsten Start zurückgebucht.

## Bauen & Starten

Voraussetzungen: macOS mit Xcode 15.4+ (empfohlen Xcode 16), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open BlackCasino.xcodeproj
```

Dann ein iPad (Gerät oder Simulator) wählen und starten. Für ein echtes Gerät im Target unter *Signing & Capabilities* das eigene Team eintragen.

Spiellogik testen (macOS oder Linux):

```bash
cd Packages/CasinoCore
swift test
```

Die GitHub-Action `.github/workflows/ci.yml` führt die Logik-Tests auf Linux aus und baut die App für den iPad-Simulator.

## Der Dealer (3D-Figur)

Ohne zusätzliche Assets baut die App einen **stilisierten Dealer aus Grundkörpern** mit Atmung, Blinzeln, Kopfbewegungen, Geben-Gesten, Nicken und Lächeln.

Für eine fotorealistische Figur kann eine Datei **`Dealer.usdz`** in `BlackCasino/Resources/` gelegt werden (wird automatisch geladen). Anforderungen:

* vollständig computergenerierte, **frei erfundene** Figur (keine reale Person nachbilden), mit Nutzungsrechten für die App
* Blendshapes nach ARKit-Benennung (`eyeBlinkLeft`, `eyeBlinkRight`, `mouthSmileLeft`, `mouthSmileRight`, …) für Gesichtsanimation
* optional eingebettete Idle-Animation; Kopf-Knoten mit „head“ im Namen für Blickrichtung

## Bekannte Grenzen / nächste Schritte

* Realistische Dealer-Figur erfordert ein externes 3D-Asset (siehe oben).
* Keine Soundeffekte (bewusst ausgelassen, da keine Audio-Assets vorliegen).
* Blackjack ohne Insurance/Surrender; Poker ohne Turniere.
* Die 3D-Kamerapositionen sind auf Querformat optimiert; Hochformat funktioniert, ist aber weniger ausgefeilt.
