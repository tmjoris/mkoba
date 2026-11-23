// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MkobaAssist",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MkobaAssist", targets: ["MkobaAssist"]),
    ],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/huggingface/AnyLanguageModel", from: "1.4.1"),
    ],
    targets: [
        .target(
            name: "MkobaAssist",
            dependencies: [
                .product(name: "MkobaCore", package: "mkoba"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
        .executableTarget(name: "mkoba-eval", dependencies: ["MkobaAssist"]),
        .testTarget(name: "MkobaAssistTests", dependencies: ["MkobaAssist"]),
    ]
)
