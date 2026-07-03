import Foundation
import PackagePlugin

@main
struct Lipservice: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "LipserviceTool")
        let configURL = sourceTarget.directoryURL.appending(path: "Secrets.yml")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "Tightlip.swift")
        return [
            makeCommand(
                executable: tool.url,
                configURL: configURL,
                outputURL: outputURL,
                displayName: target.name
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension Lipservice: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "LipserviceTool")
        let configURL = context.xcodeProject.directoryURL
            .appending(path: target.displayName)
            .appending(path: "Secrets.yml")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "Tightlip.swift")
        return [
            makeCommand(
                executable: tool.url,
                configURL: configURL,
                outputURL: outputURL,
                displayName: target.displayName
            )
        ]
    }
}
#endif

private func makeCommand(
    executable: URL,
    configURL: URL,
    outputURL: URL,
    displayName: String
) -> Command {
    var inputFiles = [configURL]
    if let envFile = envFileInput(configURL: configURL) {
        inputFiles.append(envFile)
    }
    return .buildCommand(
        displayName: "Lipservice (\(displayName))",
        executable: executable,
        arguments: [configURL.path(percentEncoded: false), outputURL.path(percentEncoded: false)],
        inputFiles: inputFiles,
        outputFiles: [outputURL]
    )
}

/// Locates the env file the tool will source, so edits to it re-trigger generation.
///
/// This mirrors TightlipCore's directive recognition (`extractEnvFileDirective`) and
/// path resolution (`resolveEnvFilePath`) just closely enough for input tracking.
/// Plugins can't depend on library targets, so the duplication is deliberate and
/// fail-open: if this scan ever disagrees with the real parser, the worst case is
/// input tracking as stale as it was before this existed — the tool remains the sole
/// source of truth for build output.
private func envFileInput(configURL: URL) -> URL? {
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

    var declared: String?
    for rawLine in text.components(separatedBy: "\n") {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty || stripped.hasPrefix("#") { continue }
        if line.first?.isWhitespace == false, stripped.hasPrefix("envFile:") {
            declared = String(stripped.dropFirst("envFile:".count))
                .trimmingCharacters(in: .whitespaces)
        }
        break
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let resolved: URL
    switch declared {
    case nil:
        resolved = home.appending(path: ".zshenv")
    case "~":
        resolved = home
    case let path? where path.hasPrefix("~/"):
        resolved = home.appending(path: String(path.dropFirst(2)))
    case let path? where path.hasPrefix("/"):
        resolved = URL(fileURLWithPath: path)
    case let path?:
        resolved = configURL.deletingLastPathComponent().appending(path: path)
    }

    // Declaring a nonexistent input file makes Xcode error rather than skip. This
    // runs at every build-plan, so tracking self-heals on the first build after the
    // file appears.
    guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
    return resolved
}
