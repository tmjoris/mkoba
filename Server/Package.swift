// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MkobaServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
    ],
    targets: [
        .executableTarget(
            name: "MkobaServer",
            dependencies: [
                .product(name: "MkobaCore", package: "mkoba"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MkobaServerTests",
            dependencies: [
                "MkobaServer",
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
