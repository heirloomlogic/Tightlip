import Foundation
import TightlipCore

@main
struct LipserviceTool {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            fail("usage: LipserviceTool <config.yml> <output.swift>")
        }
        let configPath = args[1]
        let outputPath = args[2]

        let configText: String
        do {
            configText = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            fail(
                """
                Tightlip config missing at \(configPath). Create a \
                Secrets.yml at the target source root.
                """
            )
        } catch {
            fail("failed to read \(configPath): \(error)")
        }

        var environment = ProcessInfo.processInfo.environment

        do {
            let configFile = try parseYAMLConfigFile(configText, path: configPath)

            let envFileURL = resolveEnvFilePath(
                configFile.envFile ?? TightlipDefaults.envFilePath,
                configDir: URL(fileURLWithPath: configPath).deletingLastPathComponent(),
                homeDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
            // An absent default ~/.zshenv is the normal CI case and stays silent, but
            // an explicitly declared envFile that doesn't resolve is a misconfiguration
            // worth pointing at before the missing-env-var errors it will cause.
            if configFile.envFile != nil, !FileManager.default.fileExists(atPath: envFileURL.path) {
                note("declared envFile not found at \(envFileURL.path); using process environment only")
            }
            environment = captureShellEnvironment(
                envFile: envFileURL,
                processEnvironment: environment
            )

            let secrets: [ParsedSecret]
            var envName: String?

            switch configFile.secrets {
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

            // Printed before resolution so a wrong-section pick is visible right above
            // the missing-variable errors it tends to cause.
            if let envName {
                note("using environment '\(envName)'")
            }

            // Resolve every secret before failing so one build surfaces every missing
            // variable, not one per fix-rebuild cycle. Each failure gets its own
            // `error:` line (one issue each in Xcode) with its typo-hunting note.
            var resolved: [(name: String, value: String)] = []
            var missing: [ConfigError] = []
            for secret in secrets {
                do {
                    let entry = try resolveSecret(secret, environment: environment)
                    if entry.value.isEmpty {
                        note("\(secret.envVar) is set but empty; Secrets.\(secret.name) will be \"\"")
                    }
                    resolved.append(entry)
                } catch {
                    note(missingEnvVarDiagnostic(envVar: secret.envVar, environment: environment))
                    FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
                    missing.append(error)
                }
            }
            if !missing.isEmpty {
                note(
                    "set the missing variable(s) in your shell, ~/.zshenv (for Xcode.app), "
                        + "or your CI environment"
                )
                exit(1)
            }

            let output = renderSecretsEnum(resolved, environment: envName)
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

private func note(_ message: String) {
    FileHandle.standardError.write(Data("note: \(message)\n".utf8))
}
