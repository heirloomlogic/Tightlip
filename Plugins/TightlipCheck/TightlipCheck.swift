import Foundation
import PackagePlugin

/// `swift package tightlip-check [--target <name>]...`: runs the Lipservice pipeline for
/// each target's `Secrets.yml` up to, but not including, writing the generated file, and
/// reports what a build would do. LipserviceTool does the work; this plugin picks the
/// targets and passes along its own environment.
@main
struct TightlipCheck: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let candidates = context.package.targets.compactMap { target in
            (target as? SourceModuleTarget).map {
                Candidate(name: $0.name, config: $0.directoryURL.appending(path: "Secrets.yml"))
            }
        }
        try check(
            candidates,
            arguments: arguments,
            tool: try context.tool(named: "LipserviceTool").url,
            scope: "package '\(context.package.displayName)'"
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension TightlipCheck: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        // The same location the Lipservice build plugin reads in an Xcode project.
        let candidates = context.xcodeProject.targets.map {
            Candidate(
                name: $0.displayName,
                config: context.xcodeProject.directoryURL.appending(path: $0.displayName).appending(path: "Secrets.yml")
            )
        }
        try check(
            candidates,
            arguments: arguments,
            tool: try context.tool(named: "LipserviceTool").url,
            scope: "project '\(context.xcodeProject.displayName)'"
        )
    }
}
#endif

private struct Candidate {
    let name: String
    let config: URL
}

private struct CheckError: Error, CustomStringConvertible {
    let description: String
}

/// Checks every candidate that has a `Secrets.yml`, or exactly the ones `--target`
/// names, and throws when a build would fail for any of them.
private func check(_ candidates: [Candidate], arguments: [String], tool: URL, scope: String) throws {
    var extractor = ArgumentExtractor(arguments)
    let requested = extractor.extractOption(named: "target")
    guard extractor.remainingArguments.isEmpty else {
        throw CheckError(
            description: "unexpected argument(s) \(extractor.remainingArguments.joined(separator: " ")); "
                + "usage: swift package tightlip-check [--target <name>]..."
        )
    }

    let selected: [Candidate]
    if requested.isEmpty {
        selected =
            candidates
            .filter { FileManager.default.fileExists(atPath: $0.config.path(percentEncoded: false)) }
            .sorted { $0.name < $1.name }
        guard !selected.isEmpty else {
            throw CheckError(description: "no target in \(scope) has a Secrets.yml")
        }
    } else {
        // A named target is checked even without a Secrets.yml, so the tool's
        // config-missing error explains where the file belongs.
        selected = try requested.map { name in
            guard let match = candidates.first(where: { $0.name == name }) else {
                throw CheckError(description: "no target named '\(name)' in \(scope)")
            }
            return match
        }
    }

    var failed: [String] = []
    for (index, target) in selected.enumerated() {
        if index > 0 {
            // Written directly: `print` buffers, and the tool writes to the same stdout.
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["--check", target.name, target.config.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            failed.append(target.name)
        }
    }
    if !failed.isEmpty {
        throw CheckError(description: "a build would fail for \(failed.joined(separator: ", "))")
    }
}
