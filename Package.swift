// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Tightlip",
    platforms: [.macOS(.v10_15)],
    products: [
        .plugin(name: "Lipservice", targets: ["Lipservice"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "TightlipCore",
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .testTarget(
            name: "TightlipCoreTests",
            dependencies: ["TightlipCore"],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .executableTarget(
            name: "LipserviceTool",
            dependencies: ["TightlipCore"],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .plugin(
            name: "Lipservice",
            capability: .buildTool(),
            dependencies: ["LipserviceTool"],
        ),
    ]
)
