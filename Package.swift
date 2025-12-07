// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TinyLLM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TinyLLM", targets: ["TinyLLM"])
    ],
    targets: [
        .executableTarget(
            name: "TinyLLM",
            path: "Sources/TinyLLM",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
