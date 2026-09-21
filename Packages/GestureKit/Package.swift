// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GestureKit", targets: ["GestureKit"])],
    targets: [
        .target(name: "GestureKit"),
        .testTarget(name: "GestureKitTests", dependencies: ["GestureKit"], resources: [.process("Fixtures")])
    ]
)
