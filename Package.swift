// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeBuddy",
            path: "Sources/ClaudeBuddy",
            resources: [.process("Resources")]
        )
    ]
)
