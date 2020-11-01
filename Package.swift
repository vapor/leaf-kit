// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "leaf-kit",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "LeafKit", targets: ["LeafKit"]),
        .library(name: "XCTLeafKit", targets: ["XCTLeafKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.20.2"),
    ],
    targets: [
        .target(name: "LeafKit", dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio")
        ]),
        .target(name: "XCTLeafKit", dependencies: [
            .target(name: "LeafKit")
        ]),
        .testTarget(name: "LeafKitTests", dependencies: [
            .target(name: "XCTLeafKit")
        ])
    ]
)
