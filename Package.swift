// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Pastil",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pastil", targets: ["Pastil"])
    ],
    targets: [
        .executableTarget(
            name: "Pastil",
            path: "Sources/Pastil"
        )
    ]
)
