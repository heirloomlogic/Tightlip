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

        // The empty value needs the `?` marker, or resolution rejects it.
        let config = expected.map { "\($0.name): TIGHTLIP_IT_\($0.name.uppercased())\($0.value.isEmpty ? "?" : "")" }
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

    /// `public` and `package` exist so a secrets module can serve its sibling modules, so
    /// the proof compiles the generated file as its own module and reads it from another.
    @Test(arguments: [AccessLevel.package, .public])
    func widenedEnumIsVisibleFromAnotherModule(access: AccessLevel) throws {
        let result = try typecheckAcrossModules(config: "access: \(access.rawValue)\nappKey: TIGHTLIP_IT_APP_KEY")
        #expect(result.status == 0, "cross-module typecheck failed:\n\(result.output)")
    }

    /// The control for the test above: with the default level the second module can't
    /// see `Secrets`, so a pass there proves the keyword and not the harness.
    @Test func internalEnumIsInvisibleFromAnotherModule() throws {
        let result = try typecheckAcrossModules(config: "appKey: TIGHTLIP_IT_APP_KEY")
        #expect(result.status != 0)
        #expect(result.output.contains("Secrets"), "unexpected failure:\n\(result.output)")
    }

    // MARK: helpers

    /// Emits the generated file as an `AppSecrets` module, then typechecks a second module
    /// in the same SwiftPM-style package (`-package-name`) that imports it and reads
    /// `Secrets.appKey`. Visibility is a typecheck question, and the value round trip is
    /// proven above, so nothing is linked or run. Returns the second module's result.
    private func typecheckAcrossModules(config: String) throws -> (status: Int32, output: String) {
        let file = try parseYAMLConfigFile(config, path: "it.yml")
        guard case .flat(let parsed) = file.secrets else {
            Issue.record("expected .flat")
            return (-1, "")
        }
        let resolved = try parsed.map { try resolveSecret($0, environment: ["TIGHTLIP_IT_APP_KEY": "v-app"]) }
        let driver = "import AppSecrets\nlet appKey: String = Secrets.appKey\n"
        return try inScratchDirectory(generated: renderSecretsEnum(resolved, access: file.access), driver: driver) {
            tmp in
            let common = ["-swift-version", "6", "-warnings-as-errors", "-package-name", "TightlipIT"]
            let library = try run(
                "/usr/bin/xcrun",
                ["swiftc", "Tightlip.swift", "-parse-as-library", "-module-name", "AppSecrets", "-emit-module"]
                    + common,
                cwd: tmp
            )
            #expect(library.status == 0, "AppSecrets failed to compile:\n\(library.output)")
            guard library.status == 0 else { return library }
            return try run("/usr/bin/xcrun", ["swiftc", "-typecheck", "Driver.swift", "-I", "."] + common, cwd: tmp)
        }
    }

    private func compileAndRun(generated: String, driver: String, flags: [String]) throws -> String? {
        try inScratchDirectory(generated: generated, driver: driver) { tmp in
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
    }

    /// Writes `Tightlip.swift` and `Driver.swift` into a fresh temporary directory, runs
    /// `body` there, and removes the directory.
    private func inScratchDirectory<T>(generated: String, driver: String, _ body: (URL) throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tightlip-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try generated.write(to: tmp.appendingPathComponent("Tightlip.swift"), atomically: true, encoding: .utf8)
        try driver.write(to: tmp.appendingPathComponent("Driver.swift"), atomically: true, encoding: .utf8)
        return try body(tmp)
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
