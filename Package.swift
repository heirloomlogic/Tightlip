// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HeirloomSecrets",
    products: [
        .plugin(name: "InjectHeirloomSecrets", targets: ["InjectHeirloomSecrets"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "InjectHeirloomSecretsTool",
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .plugin(
            name: "InjectHeirloomSecrets",
            capability: .buildTool(),
            dependencies: ["InjectHeirloomSecretsTool"],
        ),
    ]
)
