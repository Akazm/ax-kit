// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ax-kit",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "AXKit",
            targets: ["AXKit", "AccessibilityBridging"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", .upToNextMajor(from: "0.55.0")),
        .package(url: "https://github.com/swhitty/swift-mutex", .upToNextMajor(from: "0.0.5"))
    ],
    targets: [
        .target(name: "AccessibilityBridging", publicHeadersPath: "include"),
        .target(
            name: "AXKit",
            dependencies: [
                "AccessibilityBridging",
                .product(
                    name: "Mutex",
                    package: "swift-mutex"
                )
            ],
            path: "Sources/AXKit"
        ),
        .executableTarget(
            name: "AXKitExample",
            dependencies: ["AXKit"],
            path: "AXKitExample"
        ),
        .executableTarget(
            name: "AXKitObserverExample",
            dependencies: [
                "AXKit",
                .product(
                    name: "Mutex",
                    package: "swift-mutex",
                    condition: .when(platforms: [.macOS])
                )
            ],
            path: "AXKitObserverExample"
        ),
    ]
)
