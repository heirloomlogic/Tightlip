import Foundation
import PackagePlugin

@main
struct InjectHeirloomSecrets: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "InjectHeirloomSecretsTool")
        let configURL = sourceTarget.directoryURL.appending(path: "HeirloomSecrets.yml")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "HeirloomSecrets.swift")
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

extension InjectHeirloomSecrets: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "InjectHeirloomSecretsTool")
        let configURL = context.xcodeProject.directoryURL
            .appending(path: target.displayName)
            .appending(path: "HeirloomSecrets.yml")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "HeirloomSecrets.swift")
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
    .buildCommand(
        displayName: "Inject Heirloom Secrets (\(displayName))",
        executable: executable,
        arguments: [configURL.path(percentEncoded: false), outputURL.path(percentEncoded: false)],
        inputFiles: [configURL],
        outputFiles: [outputURL]
    )
}
