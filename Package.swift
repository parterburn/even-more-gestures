// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvenMoreGestures",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EvenMoreGestures", targets: ["EvenMoreGestures"]),
        .library(name: "GestureCore", targets: ["GestureCore"])
    ],
    dependencies: [
        .package(path: "Packages/GestureKit"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "GestureCore", resources: [.process("Resources")]),
        .target(name: "AppLogic"),
        .target(name: "TouchBridge", linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .executableTarget(name: "EvenMoreGestures", dependencies: ["GestureCore", "AppLogic", "GestureKit", "TouchBridge", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
        .testTarget(name: "AppLogicTests", dependencies: ["AppLogic"])
    ]
)
