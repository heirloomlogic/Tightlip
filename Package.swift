// swift-tools-version: 6.1

import PackageDescription
import Foundation

// Dev-only tooling (swift-format linting + DocC) must not leak into downstream
// consumers' dependency graphs. SwiftPM has no first-class dev-dependencies, so
// gate them on a gitignored `.dev-tooling` sentinel, present only in Tightlip's
// own working clone (and created as a step in CI). `#filePath` anchors the lookup
// to this manifest's directory, independent of the current working directory.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path
let isDevBuild = FileManager.default.fileExists(atPath: devSentinel)

let devDependencies: [Package.Dependency] = isDevBuild
    ? [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ]
    : []

let devPlugins: [Target.PluginUsage] = isDevBuild
    ? [.plugin(name: "Persnoop", package: "Persnicket")]
    : []

let package = Package(
    name: "Tightlip",
    platforms: [.macOS(.v10_15)],
    products: [
        .plugin(name: "Lipservice", targets: ["Lipservice"]),
    ],
    dependencies: devDependencies,
    targets: [
        .target(
            name: "TightlipCore",
            plugins: devPlugins
        ),
        .testTarget(
            name: "TightlipCoreTests",
            dependencies: ["TightlipCore"],
            plugins: devPlugins
        ),
        .executableTarget(
            name: "LipserviceTool",
            dependencies: ["TightlipCore"],
            plugins: devPlugins
        ),
        .plugin(
            name: "Lipservice",
            capability: .buildTool(),
            dependencies: ["LipserviceTool"],
        ),
    ]
)
