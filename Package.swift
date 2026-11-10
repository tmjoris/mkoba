// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MkobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MkobaCore", targets: ["MkobaCore"]),
    ],
    targets: [
        .target(
            name: "MkobaCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(name: "MkobaCoreTests", dependencies: ["MkobaCore"]),
    ]
)
