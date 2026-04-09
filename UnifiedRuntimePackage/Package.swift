// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UnifiedRuntimePackage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "UnifiedRuntimeKit", targets: ["UnifiedRuntimeKit"])
    ],
    targets: [
        .target(
            name: "UnifiedRuntimeKit",
            path: "Sources/UnifiedRuntimeKit"
        ),
        .testTarget(
            name: "UnifiedRuntimeKitTests",
            dependencies: ["UnifiedRuntimeKit"],
            path: "Tests/UnifiedRuntimeKitTests"
        )
    ]
)
