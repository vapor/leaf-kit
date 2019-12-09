// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "leaf-kit",
    platforms: [
       .macOS(.v10_14)
    ],
    products: [
        .library(name: "LeafKit", targets: ["LeafKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0"),
    ],
    targets: [
        .target(name: "LeafKit", dependencies: ["NIO"]),
        .testTarget(name: "LeafKitTests", dependencies: ["LeafKit"]),
    ]
)
