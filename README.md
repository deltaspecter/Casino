# BlackCasino

**PLAY • WIN • HAVE FUN** – ein hochwertiges, rein virtuelles Casino-Spiel für das iPad.

> BlackCasino ist ausschließlich ein Unterhaltungsspiel. Alle Chips sind virtuell und haben **keinen realen Geldwert**.
> Es gibt keine Käufe, keine Einzahlungen, keine Auszahlungen, keine Kryptowährungen, keine Lootboxen und keinen Umtausch in Geld oder Sachwerte.

## Inhalt

| Bereich | Umfang |
|---|---|
| **Blackjack** | 3D-Tisch, virtueller Dealer, 1 Deck (vor jeder Runde neu gemischt), Hit / Stand / Double / Split (bis 4 Hände), S17, Blackjack 3:2 – vollständiges Regelwerk im Spiel unter „Rules“ |
| **Poker** | No-Limit Texas Hold'em gegen 1–4 KI-Gegner mit vier Spielstilen, Side-Pots, Split-Pots, drei Tischstufen – Regeln und Handrangfolge unter „Rules“ |
| **Slots** | 3 Automaten (Crimson Sevens, Midnight Gems, Dragon Fortune), 5×3 Walzen, 10 Gewinnlinien, Wild & Scatter – je Automat Regelwerk mit Gewinntabelle, Linien und Symbol-Wahrscheinlichkeiten |
| **Multiplayer** | Online/Offline-Erkennung, private Räume mit Code (Blackjack 2–5, Poker 2–6 Spieler), Freunde mit Präsenz und Einladungen, Random Match mit Bot-Angebot, Reconnect – alles über einen autoritativen Server |
| **Extras** | Startkapital 10.000 Chips, Daily Reward, Login-Serie, 3 optionale Tagesmissionen, 11 Achievements, Statistikseite, Einstellungen, einmalige Tutorial-Boni, Startpaket bei leerem Konto. **Kein XP- oder Level-System.** |

## Technologie – und warum

**SwiftUI + SceneKit, iPadOS 17+, Swift**

* **SwiftUI** liefert native, flüssige iPad-Oberflächen mit Materialien, Animationen und Touch-Verhalten, die sich wie eine echte Premium-App anfühlen – nicht wie eine Webseite.
* **SceneKit** rendert die Tische mit physikbasierten Materialien (PBR), HDR, Bloom, Vignette, Ambient Occlusion, weichen Schatten und Image-Based Lighting – Metal-beschleunigt und sehr effizient auf iPad-GPUs. Es unterstützt USDZ-Modelle mit Skelett- und Blendshape-Animation (`SCNMorpher`) für den Dealer. Die 3D-Schicht ist gekapselt (`Scene3D/`), sodass ein späterer Umstieg auf RealityKit nur diese Schicht betrifft.
* **Swift Package `CasinoCore`** enthält die komplette Spiellogik ohne UI-Abhängigkeit. Sie ist dadurch isoliert testbar (auch auf Linux/CI) und klar von der Darstellung getrennt.

## Architektur

```
BlackCasino/
├── project.yml                  XcodeGen-Projektdefinition
├── Packages/CasinoCore/         Swift Package (App + Server)
│   ├── CasinoCore               Spiellogik: RNG, Karten, Blackjack-Tisch-Engine, Hold'em, Slots, Profil
│   └── CasinoNet                Netzwerkprotokoll + geschwärzte Tisch-Snapshots (gemeinsam für App & Server)
├── Server/                      Autoritativer Spielserver (Swift, Hummingbird 2, WebSocket)
│   ├── BlackCasinoServerCore    GameServer-Actor, Konten, Räume, Matchmaking, Poker-/Blackjack-Sitzungen
│   ├── BlackCasinoServer        Startprogramm (PORT, DATA_DIR)
│   └── Dockerfile               Container-Build
└── BlackCasino/                 iPad-App
    ├── App/                     App-Einstieg, AppModel, Navigation
    ├── Design/                  Design-System
    ├── Scene3D/                 SceneKit-Bühne, Tisch, Karten, Chips, Dealer
    ├── Screens/                 Laden, Start, Menü, Belohnungen, Statistik, Einstellungen, Rules
    ├── Games/                   Offline-Spiele (Blackjack, Poker gegen Bots, Slots)
    └── Online/                  Verbindungsstatus, Online-Client, Multiplayer-Ansichten, Online-Tische
```

**Gleiche Regeln online und offline:** Blackjack läuft immer über `BlackjackTableEngine` (offline mit einem Platz,
online mit bis zu fünf), Poker immer über `HoldemEngine`. Nur die Netzwerkschicht unterscheidet sich.

### Online-Architektur

```
iPad-App (OnlineService) ──WebSocket/JSON──▶ GameServer (Actor) ──▶ PokerSession / BlackjackSession ──▶ CasinoCore-Engines
        ▲                                         │
        └──────── TableSnapshot (pro Spieler geschwärzt) ◀┘        AccountStore (Konten, Online-Chips, Freunde)
```

* **Server-Autorität:** Deck, Kartenausgabe, Einsätze, Pot, Reihenfolge, Gewinner und Online-Kontostände existieren nur auf dem Server.
  Clients senden Absichten (`TableActionRequest`), der Server prüft Zug, Legalität, Einsatzgrenzen und Guthaben.
* **Keine Informationslecks:** Snapshots werden pro Empfänger erzeugt – fremde Hole Cards (vor dem Showdown), die verdeckte Dealer-Karte und das Deck werden nie übertragen.
* **Synchronisation:** Jeder Zustand hat eine `version`; alle Spieler erhalten nach jeder Änderung denselben öffentlichen Zustand. Clients übernehmen nie ältere Versionen.
* **Doppelte Aktionen:** Jede Aktion hat eine `actionID`; der Server verarbeitet jede ID genau einmal. Der Client sperrt Buttons, bis die Antwort da ist (`ActionGate`). Veraltete Stände (`stateVersion`) werden abgelehnt.
* **Latenz:** Buttons reagieren sofort (Haptik, Sperre), der neue Zustand kommt vom Server.
* **Reconnect:** Verbindungsabbruch → Overlay „Verbindung verloren – Versuche Verbindung wiederherzustellen …“, exponentielle Wiederholversuche, Aktionen gesperrt, keine lokalen Ergebnisse. Der Server hält den Platz 60 s; läuft die Bedenkzeit ab, gilt Stand (Blackjack) bzw. Check/Fold (Poker). Danach wird der Platz frei und der Stack dem Online-Konto gutgeschrieben.
* **Matchmaking:** 1. freier Platz an einem öffentlichen Tisch mit echten Spielern, 2. wartender Spieler fürs gleiche Spiel, 3. nach 12 s „Kein Spieler gefunden. Mit Bots spielen?“ (JA / WARTEN).
* **Bots:** Poker-Bots (vorsichtig, ausgewogen, aggressiv) entscheiden nur mit `PokerAIContext`; Blackjack-Bots mit eigener Hand + offener Dealer-Karte (Grundstrategie). Sie haben keinen Zugriff auf Deck oder RNG und sind im Spiel als „BOT“ gekennzeichnet.
* **Online-Chips:** Getrennt vom lokalen Offline-Kontostand und ausschließlich serverseitig gespeichert/validiert. Dadurch gibt es keine Konflikte zwischen lokalem und Server-Zustand. Ebenfalls rein virtuell.
* **Sicherheit:** Zugangstoken (256 Bit) in der iOS-Keychain, serverseitig nur als SHA-256-Hash gespeichert; Nachrichten max. 64 KB; Rate-Limit; Namen werden bereinigt.

### Benötigte Backend-Komponenten

| Komponente | Umsetzung im Repo | Für den Produktivbetrieb |
|---|---|---|
| Spielserver (WebSocket) | `Server/` – fertig, getestet | auf einem Host/Container betreiben (`Server/Dockerfile`) |
| TLS (`wss://`) | – | Reverse Proxy (z. B. Caddy/nginx/Load Balancer) mit Zertifikat vor dem Server |
| Persistenz (Konten, Online-Chips, Freunde) | JSON-Datei mit atomarem Schreiben (`DATA_DIR`) | für eine Instanz ausreichend; bei mehreren Instanzen `AccountStore` gegen eine Datenbank (z. B. PostgreSQL) tauschen |
| Skalierung über mehrere Instanzen | – (eine Instanz hält alle Tische im Speicher) | Sticky Sessions oder Tisch-Sharding + gemeinsamer Speicher für Präsenz/Räume |
| Monitoring | `GET /health` | an das Monitoring anbinden |

Die Serveradresse der App steht in `Info.plist` (`BCServerURL`) und kann in den Einstellungen geändert werden.

**Server lokal starten:**

```bash
cd Server
swift run BlackCasinoServer          # lauscht auf ws://localhost:8080/ws
# oder als Container:
docker build -f Server/Dockerfile -t blackcasino-server . && docker run -p 8080:8080 blackcasino-server
```

Im iPad-Simulator funktioniert `ws://localhost:8080/ws` direkt; auf einem echten iPad in den Einstellungen die IP des Rechners eintragen (z. B. `ws://192.168.1.20:8080/ws`).

### Offline-Modus

Ohne Internet bleiben Blackjack (lokaler Dealer), Poker gegen lokale Bots, Slots, Statistik, Daily Reward, Missionen, Achievements, Einstellungen, Tutorials und Regeln voll nutzbar.
Multiplayer-Kacheln zeigen „Offline nicht verfügbar“; ein Tipp darauf erklärt: „Für Multiplayer wird eine Internetverbindung benötigt.“
Ein Wechsel zwischen Online und Offline verändert laufende Offline-Spiele nicht.

## Zufall & Fairness

Grundsatz: **RNG → Mischen bzw. Walzenstopp → Ausgabe → Spielregeln → Ergebnis** – niemals umgekehrt.

* Karten und Walzen nutzen ausschließlich `SystemRandomSource` → `SystemRandomNumberGenerator` (kryptografisch sicher). Nicht-Spiel-Zufall (Missionsauswahl, KI-Spielstil, Optik) nutzt eine **getrennte** Quelle.
* Die Engines (`BlackjackEngine`, `HoldemEngine`, `SlotMachine`) kennen das Spielerprofil nicht. Kontostand, Verlauf, Uhrzeit, Missionen, Erfolge und Daily Rewards können Ergebnisse daher technisch nicht beeinflussen. Es gibt keine Win-/Loss-Streak-, Comeback- oder Pity-Logik.
* Blackjack: 1 Deck, **vor jeder Runde** per Fisher-Yates neu gemischt – jede Runde ist unabhängig von der vorherigen.
* Poker: pro Hand frisch gemischtes 52-Karten-Deck mit Burn-Karten. Die KI sieht nur `PokerAIContext` (eigene Karten, Board, Pot, Einsätze).
* Slots: Jede Walze stoppt an einer unabhängig, gleichverteilt gezogenen Position ihres festen Streifens. Das Ergebnis wird **vor** der Animation berechnet und verbucht; die Walzen zeigen es nur an.
* Die theoretische Auszahlungsquote wird exakt berechnet und im Spiel angezeigt (Crimson Sevens 95,1 %, Midnight Gems 94,2 %, Dragon Fortune 94,9 %).
* Chips auf dem Tisch liegen auf einem Treuhand-Konto. Wird die App mitten in einer Runde beendet, wird die Runde storniert und der Einsatz beim nächsten Start zurückgebucht. Der Kontostand kann nicht negativ werden.

### Tests (`Packages/CasinoCore/Tests`, `Server/Tests`)

* **Blackjack:** Blackjack 3:2, Bust, Push, Dealer-Bust, Dealer-Blackjack, beide Blackjack, Soft 17, Soft-Hände, Double, Split, Split-Asse, Double nach Split, ungültige Aktionen, 20.000+ Zufallsrunden ohne doppelte Karten
* **Poker:** alle Handkategorien inkl. Royal Flush, offizielle Rangfolge, Kicker, Split-Pot, Side-Pots, Fold ohne Showdown, Aktionsreihenfolge, Mindest-Raise, Big-Blind-Option, Chip-Erhaltung über 2.000 Hände
* **Slots:** jede Gewinnkombination (3/4/5) aller Automaten, Wild-Ersatz, Scatter 0–5, keine Gewinne, Einsatzskalierung, niedriger Kontostand, exakte vs. simulierte RTP
* **RNG:** gleichverteiltes Mischen (Chi²), keine Dubletten, Vielfalt, gleichverteilte Walzenstopps, Unabhängigkeit vom vorherigen Ergebnis, von Einsatz/Kontostand und von Missionen/Erfolgen/Daily Rewards
* **Speicherung:** alte und unvollständige Spielstände, beschädigte Dateien, negative Werte
* **Mehrplatz-Blackjack:** drei Spieler (Hit/Stand/Double) gegen einen Dealer, Unabhängigkeit der Plätze, keine doppelten Karten, Bot-Strategie
* **Protokoll:** Kodierung aller Nachrichten, Raumcodes, Schutz vor Doppelaktionen, Reconnect-Grenzen
* **Server:** Registrierung/Token-Login, Freunde & Präsenz, Räume (Code, Limits, Host-Rechte, Einladung), Matchmaking (Paarung, Bot-Angebot, Warten, Abbrechen), synchrone Poker-Hände ohne Kartenlecks, abgelehnte doppelte/veraltete/fremde Aktionen, Turn-Timeout, Blackjack-Abrechnung über das Server-Wallet, verdeckte Dealer-Karte, Reconnect innerhalb der Frist, Abbau nach Fristablauf ohne Chipverlust, Neustart mit Rückbuchung, Rate-Limit, echte WebSocket-Verbindung

## Web-App fürs iPad (als App auf dem Home-Bildschirm) – kostenlos, ohne Mac

**Link zum Spielen:** https://deltaspecter.github.io/Casino/

BlackCasino gibt es zusätzlich als Web-App (`web/`). Sie läuft in Safari und lässt sich wie eine echte App installieren:

1. Link in **Safari** auf dem iPad öffnen.
2. **Teilen** (Quadrat mit Pfeil) → **„Zum Home-Bildschirm“** → „Hinzufügen“.
3. BlackCasino startet ab dann über das eigene Symbol – im Vollbild, ohne Browserleiste und auch **offline**.

Freunde bekommen denselben Link (im Menü: **„Freunde einladen“**) und installieren die App genauso.

| | |
|---|---|
| Spiele | Blackjack, Texas Hold'em gegen KI, 3 Slot-Automaten – gleiche Regeln, Zahlen und Texte wie die iPad-App |
| Spiellogik | `web/src/core` – 1:1-Übertragung von `CasinoCore` nach TypeScript (Web-Crypto-Zufall, Fisher-Yates, exakte RTP-Berechnung) |
| Multiplayer | `web/src/net` – spricht exakt dasselbe Protokoll wie die iPad-App mit demselben Server |
| Offline | Service Worker speichert alle Dateien; Spielstand liegt lokal im Gerät (`localStorage`) |
| Tests | `cd web && npm test` (Spiellogik, Zufall, Protokoll, Online-Dienst) |

**Veröffentlichung:** Der Workflow `.github/workflows/web.yml` testet, baut und veröffentlicht die Web-App bei jedem Push auf den Standard-Branch auf GitHub Pages. Einmalig nötig: *Settings → Pages → Source: „GitHub Actions“*.

**Multiplayer-Server (optional):** Online-Spiele brauchen den Server aus `Server/`. Kostenlos geht das z. B. bei Render mit der Blueprint-Datei `render.yaml` (https://render.com/deploy?repo=https://github.com/deltaspecter/Casino). Danach die Adresse `wss://<name>.onrender.com/ws` als Repository-Variable `BLACKCASINO_SERVER_URL` eintragen (*Settings → Secrets and variables → Actions → Variables*) oder in der App unter *Settings → Serveradresse*. Im kostenlosen Tarif schläft der Server nach 15 Minuten ohne Nutzung ein (erster Verbindungsaufbau dauert dann bis zu einer Minute) und Online-Konten beginnen nach einem Neustart neu.

**Lokal entwickeln:** `cd web && npm install && npm run dev`

## Auf dem iPad öffnen – ohne Mac (Swift Playgrounds)

1. Auf dem iPad **Swift Playgrounds** aus dem App Store laden (kostenlos, iPadOS 17 oder neuer).
2. In Safari das Repository als ZIP laden: GitHub → Branch `claude/blackcasino-ipad-app` → **Code → Download ZIP**.
3. In der **Dateien**-App die ZIP antippen (wird entpackt) und darin **`BlackCasino.swiftpm`** antippen → öffnet sich in Swift Playgrounds.
4. Oben auf **▶︎** tippen – die App startet. Über das Vollbild-Symbol läuft sie bildschirmfüllend.

`BlackCasino.swiftpm` wird mit `python3 scripts/make_playgrounds.py` aus denselben Quellen erzeugt wie das Xcode-Projekt (gleiche Regeln, gleicher Code); die CI prüft, dass es aktuell ist und baut.

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

Die GitHub-Action `.github/workflows/ci.yml` führt die Logik- und Servertests auf Linux aus und baut die App für den iPad-Simulator.

## Der Dealer (3D-Figur)

Ohne zusätzliche Assets baut die App einen **stilisierten Dealer aus Grundkörpern** mit Atmung, Blinzeln, Kopfbewegungen, Geben-Gesten, Nicken und Lächeln.

Für eine fotorealistische Figur kann eine Datei **`Dealer.usdz`** in `BlackCasino/Resources/` gelegt werden (wird automatisch geladen). Anforderungen:

* vollständig computergenerierte, **frei erfundene** Figur (keine reale Person nachbilden), mit Nutzungsrechten für die App
* Blendshapes nach ARKit-Benennung (`eyeBlinkLeft`, `eyeBlinkRight`, `mouthSmileLeft`, `mouthSmileRight`, …) für Gesichtsanimation
* optional eingebettete Idle-Animation; Kopf-Knoten mit „head“ im Namen für Blickrichtung

## Bekannte Grenzen / nächste Schritte

* Realistische Dealer-Figur erfordert ein externes 3D-Asset (siehe oben).
* Keine Soundeffekte (bewusst ausgelassen, da keine Audio-Assets vorliegen).
* Blackjack ohne Insurance/Surrender; Poker ohne Turniere; Slots ohne Bonusspiele.
* Die 3D-Kamerapositionen sind auf Querformat optimiert; Hochformat funktioniert, ist aber weniger ausgefeilt.
