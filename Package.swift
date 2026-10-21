// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Podium",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PodiumCore"),
        .executableTarget(
            name: "Podium",
            dependencies: ["PodiumCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "PodiumCoreTests", dependencies: ["PodiumCore"]),
    ]
)
