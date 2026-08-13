// swift-tools-version: 6.1

import PackageDescription
import Foundation

let package = Package(
    name: "Tightlip",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .plugin(name: "Lipservice", targets: ["Lipservice"]),
    ],
    targets: [
        .target(name: "TightlipCore"),
        .testTarget(name: "TightlipCoreTests", dependencies: ["TightlipCore"]),
        .executableTarget(name: "LipserviceTool", dependencies: ["TightlipCore"]),
        .plugin(
            name: "Lipservice",
            capability: .buildTool(),
            dependencies: ["LipserviceTool"],
        ),
    ]
)

// MARK: - Dev-only tooling
//
// Dev-only tooling (the Persnoop swift-format linter and the DocC command plugin) must not
// leak into downstream consumers' dependency graphs. A build-tool plugin attached to a
// shipping target follows that target into every consumer — as a forced "trust and enable"
// prompt in Xcode, not merely a wasted checkout. SwiftPM has no first-class dev
// dependencies, so gate them on a gitignored `.dev-tooling` sentinel, present only in
// Tightlip's own working clone (and created as a CI step, before the first resolve).
//
// `#filePath` anchors the lookup to this manifest's directory, independent of the current
// working directory. Attaching the plugin here, after the package is constructed, keeps the
// target list above free of gating noise.
//
// Toggling the sentinel on an already-evaluated package requires `swift package purge-cache`:
// SwiftPM caches the evaluated manifest keyed on its source text alone, so a gate that reads
// an external file is invisible to that cache key.

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path

if FileManager.default.fileExists(atPath: devSentinel) {
    package.dependencies += [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ]
    for target in package.targets where target.type != .plugin && target.type != .binary {
        target.plugins = (target.plugins ?? []) + [.plugin(name: "Persnoop", package: "Persnicket")]
    }
}
