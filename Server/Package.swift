// swift-tools-version:5.9
import PackageDescription

/// Autoritativer Spielserver für den Online-Modus von BlackCasino.
/// Nutzt dieselbe Spiellogik (CasinoCore) wie die App – online gelten exakt die Offline-Regeln.
let package = Package(
    name: "BlackCasinoServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BlackCasinoServer", targets: ["BlackCasinoServer"])
    ],
    dependencies: [
        .package(path: "../Packages/CasinoCore"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
    ],
    targets: [
        .target(name: "BlackCasinoServerCore", dependencies: [
            .product(name: "CasinoCore", package: "CasinoCore"),
            .product(name: "CasinoNet", package: "CasinoCore"),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .executableTarget(name: "BlackCasinoServer", dependencies: ["BlackCasinoServerCore"]),
        .testTarget(name: "BlackCasinoServerTests", dependencies: [
            "BlackCasinoServerCore",
            .product(name: "HummingbirdWSClient", package: "hummingbird-websocket"),
            .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            .product(name: "HummingbirdTesting", package: "hummingbird")
        ])
    ]
)
