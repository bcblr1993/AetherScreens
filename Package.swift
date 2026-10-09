// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AetherScreens",
    defaultLocalization: "en",
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
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "5.7.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0")
    ],
    targets: [
        .target(name: "AetherScreensCatalog", path: "Sources/AetherScreensCatalog",
                linkerSettings: [.linkedFramework("CoreServices", .when(platforms: [.macOS]))]),
        .target(
            name: "AetherScreensCore",
            dependencies: [
                .target(name: "AetherScreensCatalog", condition: .when(platforms: [.macOS])),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            path: "Sources/AetherScreensCore",
            resources: [.process("Resources")]
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
