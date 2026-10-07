// swift-tools-version: 5.9
// Automatisch erzeugt von scripts/make_playgrounds.py – nicht von Hand bearbeiten.
// Öffnen auf dem iPad: Datei in der „Dateien“-App antippen → öffnet Swift Playgrounds → ▶︎
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "BlackCasino",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "BlackCasino",
            targets: ["AppModule"],
            bundleIdentifier: "com.blackcasino.playgrounds",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait,
                .portraitUpsideDown
            ],
            capabilities: [
                .localNetwork(purposeString: "BlackCasino verbindet sich für Multiplayer mit einem Spielserver in deinem Netzwerk.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
