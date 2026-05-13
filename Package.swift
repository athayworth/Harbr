// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Harbr",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .target(
            name: "HarbrSafe",
            path: "Sources/HarbrSafe",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Harbr",
            dependencies: ["HarbrSafe"],
            path: "Sources/Harbr",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
