// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DynamicIslandMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIslandMac", targets: ["DynamicIslandMac"])
    ],
    targets: [
        .executableTarget(
            name: "DynamicIslandMac",
            path: "Sources/DynamicIslandMac"
        )
    ]
)
