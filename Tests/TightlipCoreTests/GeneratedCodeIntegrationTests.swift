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
        let prints = expected.map {
            "print(Data(Secrets.\($0.name).utf8).base64EncodedString())"
        }.joined(separator: "\n")
        let driver = """
            import Foundation
            @main struct Driver {
                static func main() {
            \(prints)
                }
            }
            """
        let output = try compileAndRun(generated: generated, driver: driver, flags: ["-parse-as-library"])
        guard let output else { return }
        let printed = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let decoded = printed.prefix(expected.count).map { line in
            Data(base64Encoded: line).map { String(decoding: $0, as: UTF8.self) } ?? "<bad base64>"
        }
        // Properties are emitted alphabetically; the driver prints in `expected`
        // order, so compare in that same order.
        #expect(decoded == expected.map(\.value))
    }

    /// Compiler settings consumers commonly build with. Each must compile the generated
    /// file cleanly — as an error, not a warning.
    static let strictModes: [[String]] = {
        var modes: [[String]] = [
            ["-swift-version", "5", "-warnings-as-errors"],
            ["-swift-version", "6", "-warnings-as-errors"],
            [
                "-swift-version", "6", "-warnings-as-errors", "-enable-upcoming-feature", "ExistentialAny",
                "-enable-upcoming-feature", "MemberImportVisibility",
                "-enable-upcoming-feature", "InternalImportsByDefault",
            ],
        ]
        #if compiler(>=6.2)
        modes.append(["-swift-version", "6", "-warnings-as-errors", "-default-isolation", "MainActor"])
        modes.append(["-swift-version", "6", "-warnings-as-errors", "-strict-memory-safety"])
        #endif
        return modes
    }()

    @Test(arguments: strictModes)
    func generatedEnumCompilesUnderStrictSettingsBesideShadowingTypes(flags: [String]) throws {
        // Property names that used to be reserved because the decode shim referenced
        // them unqualified, plus consumer types that would capture those references.
        let names = ["Data", "String", "UInt8", "UTF8", "fatalError", "open", "Secrets", "encoded"]
        let config = names.map { "\($0): TIGHTLIP_IT_\($0.uppercased())" }.joined(separator: "\n")
        let environment = Dictionary(uniqueKeysWithValues: names.map { ("TIGHTLIP_IT_\($0.uppercased())", "v-\($0)") })
        guard case .flat(let parsed) = try parseYAMLConfig(config, path: "it.yml") else {
            Issue.record("expected .flat")
            return
        }
        let generated = renderSecretsEnum(try parsed.map { try resolveSecret($0, environment: environment) })

        let driver = """
            struct Data { var x = 1 }
            struct UTF8 {}
            @main struct Driver {
                static func main() {
                    print([\(names.map { "Secrets.\($0)" }.joined(separator: ", "))].joined(separator: ","))
                }
            }
            """
        let output = try compileAndRun(generated: generated, driver: driver, flags: flags + ["-parse-as-library"])
        #expect(output == names.map { "v-\($0)" }.joined(separator: ",") + "\n")
    }

    // MARK: helpers

    private func compileAndRun(generated: String, driver: String, flags: [String]) throws -> String? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tightlip-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try generated.write(to: tmp.appendingPathComponent("Tightlip.swift"), atomically: true, encoding: .utf8)
        try driver.write(to: tmp.appendingPathComponent("Driver.swift"), atomically: true, encoding: .utf8)

        let binary = tmp.appendingPathComponent("app")
        let compile = try run(
            "/usr/bin/xcrun",
            ["swiftc", "Tightlip.swift", "Driver.swift", "-o", binary.path] + flags,
            cwd: tmp
        )
        #expect(compile.status == 0, "swiftc \(flags) failed:\n\(compile.output)")
        guard compile.status == 0 else { return nil }
        let execute = try run(binary.path, [], cwd: tmp)
        #expect(execute.status == 0)
        return execute.output
    }

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
