// swift-tools-version:5.9
import PackageDescription

/// Reine Spiellogik von BlackCasino – ohne UI-Abhängigkeiten.
/// Läuft auf iPadOS/macOS und (für CI/Tests) auch auf Linux.
let package = Package(
    name: "CasinoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CasinoCore", targets: ["CasinoCore"])
    ],
    targets: [
        .target(name: "CasinoCore"),
        .testTarget(name: "CasinoCoreTests", dependencies: ["CasinoCore"])
    ]
)
