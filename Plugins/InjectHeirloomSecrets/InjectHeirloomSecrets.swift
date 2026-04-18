import Foundation
import PackagePlugin

@main
struct InjectHeirloomSecrets: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "InjectHeirloomSecretsTool")
        let configURL = sourceTarget.directoryURL.appending(path: "HeirloomSecrets.json")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "HeirloomSecrets.swift")

        return [
            .buildCommand(
                displayName: "Inject Heirloom Secrets (\(target.name))",
                executable: tool.url,
                arguments: [configURL.path(percentEncoded: false), outputURL.path(percentEncoded: false)],
                inputFiles: [configURL],
                outputFiles: [outputURL]
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
            .appending(path: "HeirloomSecrets.json")
        let outputURL = context.pluginWorkDirectoryURL.appending(path: "HeirloomSecrets.swift")

        return [
            .buildCommand(
                displayName: "Inject Heirloom Secrets (\(target.displayName))",
                executable: tool.url,
                arguments: [configURL.path(percentEncoded: false), outputURL.path(percentEncoded: false)],
                inputFiles: [configURL],
                outputFiles: [outputURL]
            )
        ]
    }
}
#endif
