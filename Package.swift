// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AetherScreens",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AetherScreensCore",
            targets: ["AetherScreensCore"]
        ),
        .executable(
            name: "AetherScreensApp",
            targets: ["AetherScreensApp"]
        )
    ],
    dependencies: [
        // Pure Swift, zero external dependencies for maximum stability, performance, and security
    ],
    targets: [
        .target(
            name: "AetherScreensCore",
            dependencies: [],
            path: "Sources/AetherScreensCore"
        ),
        .executableTarget(
            name: "AetherScreensApp",
            dependencies: ["AetherScreensCore"],
            path: "Sources/AetherScreensApp"
        ),
        .testTarget(
            name: "AetherScreensCoreTests",
            dependencies: ["AetherScreensCore"],
            path: "Tests/AetherScreensCoreTests"
        )
    ]
)
