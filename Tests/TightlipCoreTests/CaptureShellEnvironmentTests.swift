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

    @Test func disownedBackgroundChildDoesNotHangOrDiscardResult() throws {
        // A daemon-style process spawned by the env file (ssh-agent, version
        // managers) inherits the stdout pipe and can hold it open long after
        // zsh exits. Sourcing succeeded, so the exports must still come
        // through — promptly, without waiting for the grandchild.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_DAEMON_TEST=ok\nsleep 8 &!\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        let start = ContinuousClock.now
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: [:],
            timeout: 2
        )
        let elapsed = ContinuousClock.now - start

        #expect(result["TIGHTLIP_DAEMON_TEST"] == "ok")
        #expect(elapsed < .seconds(5), "took \(elapsed); blocked on the grandchild's pipe")
    }

    @Test func timeoutReturnsPromptly() throws {
        // The fallback must happen at ~timeout even though the sourced file
        // keeps running long past it.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "sleep 8\nexport NEVER_VISIBLE=1\n".write(to: envFile, atomically: true, encoding: .utf8)

        let start = ContinuousClock.now
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"],
            timeout: 0.3
        )
        let elapsed = ContinuousClock.now - start

        #expect(result == ["FALLBACK": "yes"])
        #expect(elapsed < .seconds(5), "took \(elapsed); timeout did not take effect")
    }

    @Test func sigtermIgnoringEnvFileStillTimesOutPromptly() throws {
        // `trap '' TERM` set while sourcing persists in the subshell, so the
        // timeout's SIGTERM is ignored. The capture must still return at
        // ~timeout instead of blocking until the subshell finishes.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "trap '' TERM\nsleep 8\nexport NEVER_VISIBLE=1\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        let start = ContinuousClock.now
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"],
            timeout: 0.3
        )
        let elapsed = ContinuousClock.now - start

        #expect(result == ["FALLBACK": "yes"])
        #expect(elapsed < .seconds(5), "took \(elapsed); SIGTERM-immune subshell blocked the build")
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
