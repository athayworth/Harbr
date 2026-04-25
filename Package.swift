// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Harbr",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "Harbr",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
