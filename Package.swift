// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Win2Race",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Win2Race", targets: ["Win2Race"])
    ],
    targets: [
        .executableTarget(
            name: "Win2Race",
            path: "Sources/Win2Race"
        ),
        .testTarget(
            name: "Win2RaceTests",
            dependencies: [
                .target(name: "Win2Race")
            ],
            path: "Tests/Win2RaceTests"
        )
    ]
)
