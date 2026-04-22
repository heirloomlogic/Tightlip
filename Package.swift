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
        .target(
            name: "HeirloomSecretsCore",
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .testTarget(
            name: "HeirloomSecretsCoreTests",
            dependencies: ["HeirloomSecretsCore"],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .executableTarget(
            name: "InjectHeirloomSecretsTool",
            dependencies: ["HeirloomSecretsCore"],
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
