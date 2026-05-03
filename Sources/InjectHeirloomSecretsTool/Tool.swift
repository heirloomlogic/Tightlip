import Foundation
import HeirloomSecretsCore

@main
struct InjectHeirloomSecretsTool {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            fail("usage: InjectHeirloomSecretsTool <config.yml> <output.swift>")
        }
        let configPath = args[1]
        let outputPath = args[2]

        let configText: String
        do {
            configText = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            fail(
                """
                HeirloomSecrets config missing at \(configPath). Create a \
                HeirloomSecrets.yml at the target source root.
                """
            )
        } catch {
            fail("failed to read \(configPath): \(error)")
        }

        do {
            let environment = ProcessInfo.processInfo.environment
            let config = try parseYAMLConfig(configText, path: configPath)

            let secrets: [ParsedSecret]
            var envName: String?

            switch config {
            case .flat(let parsed):
                secrets = parsed
            case .sectioned(let sections):
                let resolved = try resolveEnvironment(sections: sections, environment: environment)
                envName = resolved
                guard let section = sections.first(where: { $0.name == resolved }) else {
                    fail("internal error: resolved environment '\(resolved)' not found in sections")
                }
                secrets = section.secrets
            }

            let resolved = try secrets.map { try resolveSecret($0, environment: environment) }
            let output = renderSecretsEnum(resolved, environment: envName)
            try output.write(toFile: outputPath, atomically: true, encoding: .utf8)

            if let envName {
                FileHandle.standardError.write(Data("note: using environment '\(envName)'\n".utf8))
            }
        } catch let error as ConfigError {
            fail(error.message)
        } catch {
            fail("failed to write \(outputPath): \(error)")
        }
    }
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}
