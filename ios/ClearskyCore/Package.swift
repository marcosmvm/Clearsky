// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClearskyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClearskyCore", targets: ["ClearskyCore"])
    ],
    targets: [
        .target(
            name: "ClearskyCore"
        ),
        .testTarget(
            name: "ClearskyCoreTests",
            dependencies: ["ClearskyCore"]
        )
    ]
)
