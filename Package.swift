// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "WiredBot",
    defaultLocalization: "en",
    platforms: [.macOS("13.0")],
    products: [
        .executable(
            name: "WiredBot",
            targets: ["WiredBotExecutable"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/nark/WiredSwift", .branch("main")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "WiredBotExecutable",
            dependencies: [
                .product(name: "WiredSwift", package: "WiredSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/WiredBot"
        )
    ]
)
