// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "WiredBot",
    defaultLocalization: "en",
    platforms: [.macOS("13.0")],
    products: [
        .library(
            name: "WiredBotCore",
            targets: ["WiredBotCore"]
        ),
        .executable(
            name: "WiredBot",
            targets: ["WiredBotExecutable"]
        ),
        .executable(
            name: "WiredBotApp",
            targets: ["WiredBotApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/nark/WiredSwift", .branch("main")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "WiredBotCore",
            dependencies: [
                .product(name: "WiredSwift", package: "WiredSwift")
            ],
            path: "Sources/WiredBot"
        ),
        .executableTarget(
            name: "WiredBotExecutable",
            dependencies: [
                "WiredBotCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/WiredBotExecutable"
        ),
        .executableTarget(
            name: "WiredBotApp",
            dependencies: ["WiredBotCore"],
            path: "Sources/WiredBotApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
