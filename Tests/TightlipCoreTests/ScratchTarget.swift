import Foundation
import TightlipCore

/// A throwaway target directory with a `Secrets.yml` and a scratch home directory, so the
/// machine's real `~/.zshenv` is never sourced. Runs the build tool's entry points
/// against it.
final class ScratchTarget {
    let root: URL
    let directory: URL
    let home: URL
    var configURL: URL { directory.appendingPathComponent("Secrets.yml") }
    var outputURL: URL { directory.appendingPathComponent("Tightlip.swift") }
    var forwardedURL: URL { directory.appendingPathComponent("forwarded-environment") }

    /// Writes `config` as `Secrets.yml` unless nil, and `envFile` as `secrets.env` beside it.
    init(config: String?, envFile: String? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tightlip-scratch-\(UUID().uuidString)")
        directory = root.appendingPathComponent("target")
        home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let config {
            try config.write(to: configURL, atomically: true, encoding: .utf8)
        }
        if let envFile {
            try envFile.write(to: directory.appendingPathComponent("secrets.env"), atomically: true, encoding: .utf8)
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

    func evaluate(processEnvironment: [String: String]) -> SecretsEvaluation? {
        evaluateSecretsConfig(
            configPath: configURL.path,
            forwardedEnvironmentPath: nil,
            processEnvironment: processEnvironment,
            homeDirectory: home,
            emit: { _ in }
        )
    }

    func check(processEnvironment: [String: String]) -> (succeeded: Bool, lines: [String]) {
        var lines: [String] = []
        let succeeded = checkSecretsConfig(
            configPath: configURL.path,
            displayName: "Demo",
            processEnvironment: processEnvironment,
            homeDirectory: home,
            emit: { lines.append($0) }
        )
        return (succeeded, lines)
    }

    func output() throws -> String {
        try String(contentsOf: outputURL, encoding: .utf8)
    }

    /// Decodes one property from the generated file with the salt it embeds.
    func decoded(_ property: String) throws -> String {
        try decodeGeneratedProperty(output(), propertyName: property)
    }
}
