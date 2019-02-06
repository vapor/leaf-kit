// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "leaf-kit",
    products: [
        .library(name: "LeafKit", targets: ["LeafKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .branch("master")),
    ],
    targets: [
        .target(name: "LeafKit", dependencies: ["NIO"]),
        .testTarget(name: "LeafKitTests", dependencies: ["LeafKit"]),
    ]
)
