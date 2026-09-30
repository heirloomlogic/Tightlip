// swift-tools-version: 6.1

// End-to-end fixture for CI: a standalone consumer package that attaches the
// Lipservice plugin exactly the way a downstream user would. Not referenced by the
// root manifest, so `swift test` at the repo root is unaffected. Built and executed
// by .github/workflows/test.yml.

import PackageDescription

let package = Package(
    name: "DemoApp",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        // `name:` pins the identity: a path dependency is otherwise identified by its
        // directory name, which varies across clones (worktrees, CI checkout paths).
        .package(name: "Tightlip", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DemoApp",
            // The env file is plugin input, not a source; excluding it silences
            // SwiftPM's "unhandled file" warning.
            exclude: ["secrets.env"],
            plugins: [.plugin(name: "Lipservice", package: "Tightlip")]
        ),
        .executableTarget(
            name: "SectionedDemo",
            plugins: [.plugin(name: "Lipservice", package: "Tightlip")]
        ),
    ]
)
