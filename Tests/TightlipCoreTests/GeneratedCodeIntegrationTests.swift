import Foundation
import Testing
import TightlipCore

/// End-to-end proof that the full pipeline emits Swift that actually compiles
/// and decodes back to the original values. Unit tests re-implement the XOR
/// decode; only compiling and running the real generated file catches
/// generation-validity regressions (invalid identifiers, template typos,
/// decode-shim drift).
@Suite("generated code integration", .serialized)
struct GeneratedCodeIntegrationTests {
    @Test func generatedEnumCompilesAndRoundTripsValues() throws {
        let expected: [(name: String, value: String)] = [
            (name: "simple", value: "abc123"),
            (name: "withQuotesAndBackslash", value: #"va"l\ue"#),
            (name: "withNewline", value: "line1\nline2"),
            (name: "unicode", value: "πø🦊"),
            (name: "longerThanSalt", value: String(repeating: "0123456789", count: 8)),
            (name: "empty", value: ""),
        ]

        let config = expected.map { "\($0.name): TIGHTLIP_IT_\($0.name.uppercased())" }
            .joined(separator: "\n")
        let environment = Dictionary(
            uniqueKeysWithValues: expected.map { ("TIGHTLIP_IT_\($0.name.uppercased())", $0.value) }
        )

        // Full pipeline: parse → resolve → render.
        guard case .flat(let parsed) = try parseYAMLConfig(config, path: "it.yml") else {
            Issue.record("expected .flat")
            return
        }
        let resolved = try parsed.map { try resolveSecret($0, environment: environment) }
        let generated = renderSecretsEnum(resolved)

        // Compile the generated file together with a driver that prints each
        // value base64-encoded (newline-safe), then run it.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tightlip-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let driver = expected.map {
            "print(Data(Secrets.\($0.name).utf8).base64EncodedString())"
        }.joined(separator: "\n")
        try generated.write(
            to: tmp.appendingPathComponent("Tightlip.swift"), atomically: true, encoding: .utf8)
        try "import Foundation\n\(driver)\n".write(
            to: tmp.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let binary = tmp.appendingPathComponent("app")
        let compile = try run(
            "/usr/bin/xcrun",
            ["swiftc", "Tightlip.swift", "main.swift", "-o", binary.path],
            cwd: tmp
        )
        #expect(compile.status == 0, "swiftc failed:\n\(compile.output)")
        guard compile.status == 0 else { return }

        let execute = try run(binary.path, [], cwd: tmp)
        #expect(execute.status == 0)
        let printed = execute.output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let decoded = printed.prefix(expected.count).map { line in
            Data(base64Encoded: line).map { String(decoding: $0, as: UTF8.self) } ?? "<bad base64>"
        }
        // Properties are emitted alphabetically; the driver prints in `expected`
        // order, so compare in that same order.
        #expect(decoded == expected.map(\.value))
    }

    // MARK: helpers

    private func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
