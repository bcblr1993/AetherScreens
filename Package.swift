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
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "5.7.0")
    ],
    targets: [
        .target(
            name: "AetherScreensCore",
            dependencies: [.product(name: "BigInt", package: "BigInt")],
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
