// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HeirloomSecrets",
    platforms: [.macOS(.v10_15)],
    products: [
        .plugin(name: "InjectHeirloomSecrets", targets: ["InjectHeirloomSecrets"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "HeirloomSecretsCore",
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .testTarget(
            name: "HeirloomSecretsCoreTests",
            dependencies: ["HeirloomSecretsCore"],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .executableTarget(
            name: "InjectHeirloomSecretsTool",
            dependencies: ["HeirloomSecretsCore"],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .plugin(
            name: "InjectHeirloomSecrets",
            capability: .buildTool(),
            dependencies: ["InjectHeirloomSecretsTool"],
        ),
    ]
)
