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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
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
        ).merged
        let elapsed = ContinuousClock.now - start

        #expect(result == ["FALLBACK": "yes"])
        #expect(elapsed < .seconds(5), "took \(elapsed); SIGTERM-immune subshell blocked the build")
    }

    @Test func syntaxErrorMidFileNotesPartialEnvironment() throws {
        // `source` aborts at the bad line but the subshell continues to `env -0`
        // and exits 0 — exports above the error are visible, exports below are
        // not. That partial capture must be reported, not silent.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let body = """
            export TIGHTLIP_BEFORE_ERROR=1
            if then fi garbage(
            export TIGHTLIP_AFTER_ERROR=2
            """
        try body.write(to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"],
            onNote: { notes.append($0) }
        ).merged
        #expect(result["TIGHTLIP_BEFORE_ERROR"] == "1")
        #expect(result["TIGHTLIP_AFTER_ERROR"] == nil)
        #expect(result["FALLBACK"] == "yes")
        #expect(notes.contains { $0.contains("partial") }, "notes were: \(notes)")
    }

    @Test func exitZeroInEnvFileFallsBackWithNote() throws {
        // `exit 0` while sourcing kills the subshell before `env -0` runs, so
        // nothing is captured yet the exit status is success. That must be
        // treated as a capture failure, not an empty-but-valid environment.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_BEFORE_EXIT=1\nexit 0\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["FALLBACK": "yes"],
            onNote: { notes.append($0) }
        ).merged
        #expect(result == ["FALLBACK": "yes"])
        #expect(!notes.isEmpty, "capture failure was silent")
    }

    @Test func cleanSourceEmitsNoNotes() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_CLEAN=ok\n".write(to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: [:],
            onNote: { notes.append($0) }
        ).merged
        #expect(result["TIGHTLIP_CLEAN"] == "ok")
        #expect(notes.isEmpty, "unexpected notes: \(notes)")
    }

    @Test func sourceStatusSentinelIsStripped() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export FOO=bar\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:]).merged
        #expect(result["TIGHTLIP_SOURCE_STATUS"] == nil)
    }

    @Test func leakedHelperVarIsStripped() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export FOO=bar\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:]).merged
        #expect(result["TIGHTLIP_ENV_FILE"] == nil)
    }

    @Test func directoryEnvFileFallsBackWithNote() throws {
        // zsh's `source <dir>` succeeds and exports nothing — without this check a
        // directory would be a silent no-op.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: tmp,
            processEnvironment: ["FALLBACK": "yes"],
            onNote: { notes.append($0) }
        )
        #expect(result.merged == ["FALLBACK": "yes"])
        #expect(notes.contains { $0.contains("is a directory") }, "notes were: \(notes)")
    }

    @Test func exitTrapCannotInjectEntries() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let body = """
            export TIGHTLIP_K=real
            trap 'print -n "TIGHTLIP_K=forged\\0"' EXIT
            zshexit() { print -n "TIGHTLIP_K=forged2\\0" }
            """
        try body.write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:])
        #expect(result.merged["TIGHTLIP_K"] == "real")
    }

    @Test func debugAndErrTrapsCannotInjectEntries() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let body = """
            export TIGHTLIP_K=real
            trap 'print -n "TIGHTLIP_K=forged-debug\\0"' DEBUG
            trap 'print -n "TIGHTLIP_INJ=forged-zerr\\0"' ZERR
            """
        try body.write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:])
        #expect(result.merged["TIGHTLIP_K"] == "real")
        #expect(result.merged["TIGHTLIP_INJ"] == nil)
    }

    @Test func readonlyVariablesInEnvFileDoNotBreakTheCapture() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_K=1\ntypeset -r rc=7\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(envFile: envFile, processEnvironment: [:])
        #expect(result.merged["TIGHTLIP_K"] == "1")
    }

    @Test func functionsCannotShadowTheDump() throws {
        // A function named `printf` could otherwise forge a clean source status over
        // the syntax error below.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let body = """
            export TIGHTLIP_K=1
            printf() { builtin printf 'TIGHTLIP_SOURCE_STATUS=0\\0' }
            if then fi garbage(
            """
        try body.write(to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile, processEnvironment: [:], onNote: { notes.append($0) })
        #expect(result.merged["TIGHTLIP_K"] == "1")
        #expect(notes.contains { $0.contains("partial") }, "notes were: \(notes)")
    }

    @Test func errExitInEnvFileKeepsEarlierExports() throws {
        // A trailing false conditional under ERR_EXIT used to kill the subshell and
        // discard every export; it's a partial capture, not a failed one.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "setopt err_exit\nexport TIGHTLIP_K=1\n[[ -n $TIGHTLIP_NOPE ]] && export X=1\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile, processEnvironment: [:], onNote: { notes.append($0) })
        #expect(result.merged["TIGHTLIP_K"] == "1")
        #expect(notes.contains { $0.contains("partial") }, "notes were: \(notes)")
    }

    @Test func failedDumpFallsBackInsteadOfLookingClean() throws {
        // Past ARG_MAX, `/usr/bin/env` can't even exec. printf's status used to mask
        // that and silently drop every sourced variable.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_BIG=\"$(printf '%*s' 1100000 '')\"\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile, processEnvironment: ["FALLBACK": "yes"], onNote: { notes.append($0) })
        #expect(result.merged == ["FALLBACK": "yes"])
        #expect(notes.contains { $0.contains("exited 125") }, "notes were: \(notes)")
    }

    @Test func invalidUTF8ValueIsDroppedWithNote() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_LATIN1=$'caf\\xe9'\nexport TIGHTLIP_OK=1\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        var notes: [String] = []
        let result = captureShellEnvironment(
            envFile: envFile, processEnvironment: [:], onNote: { notes.append($0) })
        #expect(result.merged["TIGHTLIP_LATIN1"] == nil)
        #expect(result.merged["TIGHTLIP_OK"] == "1")
        #expect(notes.contains { $0.contains("TIGHTLIP_LATIN1") && $0.contains("UTF-8") })
    }

    @Test func reportsKeysTheFileReassignedButTheProcessOverrode() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_ROTATED=new\nexport TIGHTLIP_SAME=same\n".write(
            to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile,
            processEnvironment: ["TIGHTLIP_ROTATED": "old", "TIGHTLIP_SAME": "same", "UNTOUCHED": "x"]
        )
        #expect(result.merged["TIGHTLIP_ROTATED"] == "old")
        #expect(result.overriddenKeys == ["TIGHTLIP_ROTATED"])
    }

    @Test func emptyFileValuesAreNotReportedAsOverridden() throws {
        // A `$(security …)` export yields "" inside the build sandbox; the build
        // environment's value winning over it is the desired outcome, not a warning.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        try "export TIGHTLIP_FROM_KEYCHAIN=\"\"\n".write(to: envFile, atomically: true, encoding: .utf8)

        let result = captureShellEnvironment(
            envFile: envFile, processEnvironment: ["TIGHTLIP_FROM_KEYCHAIN": "real"])
        #expect(result.overriddenKeys.isEmpty)
    }

    @Test(arguments: [
        "trap '' TERM\n/bin/sleep MARKER\n",
        // zsh itself dies on SIGTERM here; only the subshell ignores it.
        "( trap '' TERM; /bin/sleep MARKER )\n",
    ])
    func timeoutKillsTermIgnoringDescendants(template: String) throws {
        // SIGKILL must reach the whole process group; killing zsh alone orphans a
        // TERM-immune grandchild that outlives the build.
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let envFile = tmp.appendingPathComponent(".zshenv")
        let marker = "37.\(Int.random(in: 100_000...999_999))"
        try template.replacingOccurrences(of: "MARKER", with: marker)
            .write(to: envFile, atomically: true, encoding: .utf8)

        _ = captureShellEnvironment(envFile: envFile, processEnvironment: [:], timeout: 0.3)
        Thread.sleep(forTimeInterval: 0.3)

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "sleep \(marker)"]
        pgrep.standardOutput = FileHandle.nullDevice
        try pgrep.run()
        pgrep.waitUntilExit()
        #expect(pgrep.terminationStatus == 1, "sleep \(marker) survived the timeout")
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
