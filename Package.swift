// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Harbr",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        // Sparkle 2.x — in-app auto-updates. The integration code in
        // Sources/Harbr/UpdateManager.swift is gated on the Info.plist
        // SUPublicEDKey + SUFeedURL being set to real values, so adding
        // the dependency here is safe even before keys are generated:
        // the updater controller is never constructed until the keys
        // are filled in.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "HarbrSafe",
            path: "Sources/HarbrSafe",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Harbr",
            dependencies: [
                "HarbrSafe",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Harbr",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
