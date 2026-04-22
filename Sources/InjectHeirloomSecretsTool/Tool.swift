import Foundation
import HeirloomSecretsCore

@main
struct InjectHeirloomSecretsTool {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            fail("usage: InjectHeirloomSecretsTool <config.yaml> <output.swift>")
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
                HeirloomSecrets.yaml at the target source root.
                """
            )
        } catch {
            fail("failed to read \(configPath): \(error)")
        }

        do {
            let parsed = try parseYAMLConfig(configText, path: configPath)
            let environment = ProcessInfo.processInfo.environment
            let resolved = try parsed.map { try resolveSecret($0, environment: environment) }
            let output = renderSecretsEnum(resolved)
            try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
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
