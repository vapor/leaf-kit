// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "leaf-kit",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "LeafKit", targets: ["LeafKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0")
    ],
    targets: [
        .target(
            name: "LeafKit",
            dependencies: [
                .product(name: "NIO", package: "swift-nio")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LeafKitTests",
            dependencies: [
                .target(name: "LeafKit")
            ],
            resources: [
                .copy("Templates")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("ConciseMagicFile"),
        .enableUpcomingFeature("ForwardTrailingClosures"),
        .enableUpcomingFeature("DisableOutwardActorInference"),
        .enableUpcomingFeature("StrictConcurrency"),
        .enableExperimentalFeature("StrictConcurrency=complete"),
    ]
}
