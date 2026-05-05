// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FloatMon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FloatMon", targets: ["FloatMon"])
    ],
    targets: [
        .executableTarget(
            name: "FloatMon",
            path: "Sources/FloatMon"
        )
    ]
)
