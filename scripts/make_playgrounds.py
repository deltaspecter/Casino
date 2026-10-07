#!/usr/bin/env python3
"""Erzeugt BlackCasino.swiftpm – eine App, die direkt auf dem iPad mit Swift Playgrounds
geöffnet und gestartet werden kann (kein Mac nötig).

Die Quellen werden aus der Spiellogik (CasinoCore), dem Netzwerkprotokoll (CasinoNet)
und der App zusammengeführt. Da Swift Playgrounds ein einzelnes App-Modul baut,
werden die `import CasinoCore` / `import CasinoNet` Zeilen entfernt. Logik und Regeln
sind identisch mit der Xcode-Version.

Aufruf (im Repository-Hauptverzeichnis):  python3 scripts/make_playgrounds.py
"""
import os, re, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "BlackCasino.swiftpm")
SOURCES = [
    ("Packages/CasinoCore/Sources/CasinoCore", "Sources/CasinoCore"),
    ("Packages/CasinoCore/Sources/CasinoNet", "Sources/CasinoNet"),
    ("BlackCasino", "Sources/App"),
]

PACKAGE = '''// swift-tools-version: 5.9
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
'''

def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    count = 0
    for src, dst in SOURCES:
        for dirpath, _, files in os.walk(os.path.join(ROOT, src)):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, name), os.path.join(ROOT, src))
                target = os.path.join(OUT, dst, rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                    text = f.read()
                text = re.sub(r"^(@testable )?import Casino(Core|Net)\n", "", text, flags=re.M)
                with open(target, "w", encoding="utf-8") as f:
                    f.write(text)
                count += 1
    shutil.copytree(os.path.join(ROOT, "BlackCasino/Resources/Assets.xcassets"), os.path.join(OUT, "Assets.xcassets"))
    with open(os.path.join(OUT, "Package.swift"), "w", encoding="utf-8") as f:
        f.write(PACKAGE)
    print(f"BlackCasino.swiftpm erzeugt ({count} Swift-Dateien).")

if __name__ == "__main__":
    main()
