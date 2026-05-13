import Foundation
import Testing
import TightlipCore

@Suite("captureShellEnvironment")
struct CaptureShellEnvironmentTests {
    @Test func missingFileReturnsProcessEnvironmentUnchanged() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let absent = tmp.appendingPathComponent("nope.zshenv")

        let result = captureShellEnvironment(
            envFile: absent,
            processEnvironment: ["FOO": "bar"]
        )
        #expect(result == ["FOO": "bar"])
    }

    @Test func sourcedExportsAreVisible() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_TEST_KEY=secretvalue\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["PATH": "/usr/bin"]
        )
        #expect(result["TIGHTLIP_TEST_KEY"] == "secretvalue")
        #expect(result["PATH"] == "/usr/bin")
    }

    @Test func processEnvironmentWinsPerKey() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_OVERRIDE=from_file\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["TIGHTLIP_OVERRIDE": "from_process"]
        )
        #expect(result["TIGHTLIP_OVERRIDE"] == "from_process")
    }

    @Test func envFileWithStdoutPollutionStillParses() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let body = """
            echo "this would corrupt naive capture"
            print -l noisy garbage here
            export TIGHTLIP_AFTER_NOISE=clean
            """
        try body.write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: [:]
        )
        #expect(result["TIGHTLIP_AFTER_NOISE"] == "clean")
    }

    @Test func valueWithNewlinesSurvives() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_MULTILINE=$'line1\\nline2'\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: [:]
        )
        #expect(result["TIGHTLIP_MULTILINE"] == "line1\nline2")
    }

    @Test func timeoutFallsBackToProcessEnvironment() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "sleep 10\nexport NEVER_VISIBLE=1\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"],
            timeout: 0.3
        )
        #expect(result["NEVER_VISIBLE"] == nil)
        #expect(result["FALLBACK"] == "yes")
    }

    @Test func nonzeroExitFallsBackGracefully() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_BEFORE_EXIT=1\nexit 3\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"]
        )
        // Implementation forwards `exit` to the subshell via `source ... 2>&1`, so the
        // subshell process exit code is the source exit. With non-zero we fall back.
        #expect(result["FALLBACK"] == "yes")
        #expect(result["TIGHTLIP_BEFORE_EXIT"] == nil)
    }

    @Test func leakedHelperVarIsStripped() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export FOO=bar\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:])
        #expect(result["TIGHTLIP_ENV_FILE"] == nil)
    }

    // MARK: helpers

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tightlip-tests-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
