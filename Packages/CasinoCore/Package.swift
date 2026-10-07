// swift-tools-version:5.9
import PackageDescription

/// Spiellogik und Netzwerkprotokoll von BlackCasino – ohne UI-Abhängigkeiten.
/// Wird von der iPad-App UND vom Server genutzt, damit online und offline
/// exakt dieselben Regeln gelten. Läuft auf iPadOS, macOS und Linux.
let package = Package(
    name: "CasinoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CasinoCore", targets: ["CasinoCore"]),
        .library(name: "CasinoNet", targets: ["CasinoNet"])
    ],
    targets: [
        .target(name: "CasinoCore"),
        .target(name: "CasinoNet", dependencies: ["CasinoCore"]),
        .testTarget(name: "CasinoCoreTests", dependencies: ["CasinoCore"]),
        .testTarget(name: "CasinoNetTests", dependencies: ["CasinoNet"])
    ]
)
