import Foundation
import Testing
import TightlipCore

/// The build tool's end-to-end behavior: what it prints, whether it succeeds, and what
/// it writes. Every run uses a scratch home directory, so the machine's real
/// `~/.zshenv` is never sourced.
@Suite("generateSecretsFile")
struct GenerateSecretsFileTests {
    @Test func writesDecodableOutputAndSucceeds() throws {
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY")
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "v"])
        #expect(result.succeeded)
        #expect(result.lines.isEmpty, "unexpected output: \(result.lines)")
        #expect(try run.output().contains("static let apiKey: Swift.String"))
    }

    @Test func reportsEveryMissingVariableThenGuidanceOnce() throws {
        let run = try Run(config: "a: TIGHTLIP_GEN_A\nb: TIGHTLIP_GEN_B\nc: TIGHTLIP_GEN_C")
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_B": "set"])
        #expect(!result.succeeded)
        #expect(
            result.errors == [
                "error: environment variable TIGHTLIP_GEN_A must be set to generate Secrets.a",
                "error: environment variable TIGHTLIP_GEN_C must be set to generate Secrets.c",
            ])
        #expect(result.lines.filter { $0.contains("set the missing variable(s)") }.count == 1)
        #expect(result.lines.filter { $0.contains("with prefix 'TIGHTLIP_'") }.count == 2)
        #expect(!FileManager.default.fileExists(atPath: run.outputURL.path))
    }

    @Test func emptyValueIsAWarning() throws {
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY")
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": ""])
        #expect(result.succeeded)
        #expect(result.lines == [#"warning: TIGHTLIP_GEN_KEY is set but empty; Secrets.apiKey will be """#])
    }

    @Test func parseErrorIsAttributedToTheConfigLine() throws {
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY\n\tbad: X")
        let result = run.generate(processEnvironment: [:])
        #expect(!result.succeeded)
        #expect(result.lines.count == 1)
        #expect(result.lines[0].hasPrefix("\(run.configURL.path):2: error: "))
    }

    @Test func missingConfigSaysWhereItBelongs() throws {
        let run = try Run(config: nil)
        let result = run.generate(processEnvironment: [:])
        #expect(!result.succeeded)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].contains("Tightlip config missing at \(run.configURL.path)"))
        #expect(result.errors[0].contains("display name"))
    }

    @Test func nonUTF8ConfigIsNamedAsSuch() throws {
        let run = try Run(config: nil)
        try "apiKey: K".data(using: .utf16)!.write(to: run.configURL)
        let result = run.generate(processEnvironment: [:])
        #expect(!result.succeeded)
        #expect(
            result.lines == ["\(run.configURL.path): error: config is not valid UTF-8; save it with UTF-8 encoding"])
    }

    @Test func declaredButMissingEnvFileIsNoted() throws {
        let run = try Run(config: "envFile: ./absent.env\napiKey: TIGHTLIP_GEN_KEY")
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "v"])
        #expect(result.succeeded)
        #expect(result.lines.contains { $0.hasPrefix("note: declared envFile not found at ") })
    }

    @Test func envFileSuppliesValues() throws {
        let run = try Run(config: "envFile: ./local.env\napiKey: TIGHTLIP_GEN_KEY")
        try "export TIGHTLIP_GEN_KEY=from-file\n".write(
            to: run.directory.appendingPathComponent("local.env"), atomically: true, encoding: .utf8)
        let result = run.generate(processEnvironment: [:])
        #expect(result.succeeded, "output: \(result.lines)")
        #expect(try run.decoded("apiKey") == "from-file")
    }

    @Test func forwardedEnvironmentReachesTheTool() throws {
        // SwiftPM's swiftbuild backend hands the tool a synthesized environment; the
        // plugin's forwarded file is how a CI job's variables get through.
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY")
        try run.forward(["TIGHTLIP_GEN_KEY": "forwarded"])
        let result = run.generate(processEnvironment: ["UNRELATED": "x"])
        #expect(result.succeeded, "output: \(result.lines)")
        #expect(try run.decoded("apiKey") == "forwarded")
    }

    @Test func processEnvironmentWinsOverForwarded() throws {
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY")
        try run.forward(["TIGHTLIP_GEN_KEY": "forwarded"])
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "process"])
        #expect(result.succeeded)
        #expect(try run.decoded("apiKey") == "process")
    }

    @Test func forwardedTightlipEnvSelectsTheSection() throws {
        let run = try Run(
            config: "staging:\n  apiKey: TIGHTLIP_GEN_S\nproduction:\n  apiKey: TIGHTLIP_GEN_P")
        try run.forward(["TIGHTLIP_ENV": "production", "TIGHTLIP_GEN_P": "prod-value"])
        let result = run.generate(processEnvironment: ["CONFIGURATION": "Debug"])
        #expect(result.succeeded, "output: \(result.lines)")
        #expect(result.lines.contains("note: using environment 'production'"))
        #expect(try run.decoded("apiKey") == "prod-value")
    }

    @Test func staleBuildEnvironmentValueIsWarnedWithoutPrintingValues() throws {
        // A terminal opened before the env file was edited still exports the old value,
        // which wins per key. Say so — but never print either value.
        let run = try Run(config: "envFile: ./local.env\napiKey: TIGHTLIP_GEN_KEY")
        try "export TIGHTLIP_GEN_KEY=rotated-new\n".write(
            to: run.directory.appendingPathComponent("local.env"), atomically: true, encoding: .utf8)
        let result = run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "revoked-old"])
        #expect(result.succeeded)
        let warnings = result.lines.filter { $0.hasPrefix("warning: TIGHTLIP_GEN_KEY ") }
        #expect(warnings.count == 1, "output: \(result.lines)")
        #expect(!result.lines.joined().contains("rotated-new"))
        #expect(!result.lines.joined().contains("revoked-old"))
    }

    @Test func overriddenTightlipEnvIsOnlyANote() throws {
        // Overriding the file's TIGHTLIP_ENV for one build is routine.
        let run = try Run(
            config: "envFile: ./local.env\nstaging:\n  k: TIGHTLIP_GEN_S\nproduction:\n  k: TIGHTLIP_GEN_P")
        try "export TIGHTLIP_ENV=staging\n".write(
            to: run.directory.appendingPathComponent("local.env"), atomically: true, encoding: .utf8)
        let result = run.generate(processEnvironment: ["TIGHTLIP_ENV": "production", "TIGHTLIP_GEN_P": "p"])
        #expect(result.succeeded, "output: \(result.lines)")
        #expect(!result.lines.contains { $0.hasPrefix("warning:") }, "output: \(result.lines)")
        #expect(result.lines.contains { $0.hasPrefix("note: TIGHTLIP_ENV from the build environment overrides") })
        #expect(result.lines.contains("note: using environment 'production'"))
    }

    @Test func unchangedOutputIsNotRewritten() throws {
        // Xcode projects re-run build-tool commands on every build; rewriting an
        // identical file would recompile it every time.
        let run = try Run(config: "apiKey: TIGHTLIP_GEN_KEY")
        #expect(run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "v"]).succeeded)
        let before = try FileManager.default.attributesOfItem(atPath: run.outputURL.path)
        Thread.sleep(forTimeInterval: 0.05)
        #expect(run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "v"]).succeeded)
        let after = try FileManager.default.attributesOfItem(atPath: run.outputURL.path)
        #expect(before[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int)
        #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)

        #expect(run.generate(processEnvironment: ["TIGHTLIP_GEN_KEY": "changed"]).succeeded)
        #expect(try run.decoded("apiKey") == "changed")
    }

    // MARK: helpers

    private final class Run {
        let root: URL
        let directory: URL
        let home: URL
        var configURL: URL { directory.appendingPathComponent("Secrets.yml") }
        var outputURL: URL { directory.appendingPathComponent("Tightlip.swift") }
        var forwardedURL: URL { directory.appendingPathComponent("forwarded-environment") }

        init(config: String?) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("tightlip-generate-\(UUID().uuidString)")
            directory = root.appendingPathComponent("target")
            home = root.appendingPathComponent("home")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            if let config {
                try config.write(to: configURL, atomically: true, encoding: .utf8)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func forward(_ environment: [String: String]) throws {
            var data = Data()
            for (key, value) in environment {
                data.append(Data("\(key)=\(value)".utf8))
                data.append(0)
            }
            try data.write(to: forwardedURL)
        }

        func generate(processEnvironment: [String: String]) -> (succeeded: Bool, lines: [String], errors: [String]) {
            var lines: [String] = []
            let succeeded = generateSecretsFile(
                configPath: configURL.path,
                outputPath: outputURL.path,
                forwardedEnvironmentPath: FileManager.default.fileExists(atPath: forwardedURL.path)
                    ? forwardedURL.path : nil,
                processEnvironment: processEnvironment,
                homeDirectory: home,
                emit: { lines.append($0) }
            )
            return (succeeded, lines, lines.filter { $0.hasPrefix("error: ") })
        }

        func output() throws -> String {
            try String(contentsOf: outputURL, encoding: .utf8)
        }

        /// Decodes one property from the generated file with the salt it embeds.
        func decoded(_ property: String) throws -> String {
            try decodeGeneratedProperty(output(), propertyName: property)
        }
    }
}
