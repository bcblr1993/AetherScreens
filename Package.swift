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
        .library(name: "AetherScreensWidgetSupport", targets: ["AetherScreensWidgetSupport"]),
        .library(name: "AetherScreensSSH", targets: ["AetherScreensSSH"]),
        .library(
            name: "AetherScreensCore",
            targets: ["AetherScreensCore"]
        ),
        .executable(
            name: "AetherScreensApp",
            targets: ["AetherScreensApp"]
        ),
        .executable(name: "AetherScreensSSHUIFixture", targets: ["AetherScreensSSHUIFixture"])
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "5.7.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", exact: "0.3.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3")
    ],
    targets: [
        .target(name: "AetherScreensWidgetSupport"),
        .testTarget(name: "AetherScreensWidgetSupportTests", dependencies: ["AetherScreensWidgetSupport"]),
        .executableTarget(name: "AetherScreensSSHUIFixture", dependencies: [
            "AetherScreensSSH", .product(name: "Citadel", package: "citadel"), .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIO", package: "swift-nio"), .product(name: "Crypto", package: "swift-crypto")
        ], path: "scripts/qa/ssh_ui_fixture"),
        .target(name: "AetherScreensSSH", dependencies: [
            .product(name: "Citadel", package: "citadel"), .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .testTarget(name: "AetherScreensSSHTests", dependencies: [
            "AetherScreensSSH", "AetherScreensCore", .product(name: "Citadel", package: "citadel"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(
            name: "AetherScreensCore",
            dependencies: ["AetherScreensSSH", "AetherScreensWidgetSupport", .product(name: "BigInt", package: "BigInt")],
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
