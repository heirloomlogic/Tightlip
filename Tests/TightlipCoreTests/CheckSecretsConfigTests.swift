import Foundation
import Testing
import TightlipCore

/// The `tightlip-check` command's logic: the structured result of evaluating a config
/// (`evaluateSecretsConfig`) and the report built from it (`checkSecretsConfig`). Every
/// run uses a scratch home directory, so the machine's real `~/.zshenv` is never sourced.
@Suite("checkSecretsConfig")
struct CheckSecretsConfigTests {
    // MARK: variable status and source

    @Test func reportsEveryStateWithItsSource() throws {
        let run = try ScratchTarget(
            config: """
                envFile: ./secrets.env
                fromFile: TIGHTLIP_CHECK_FILE
                fromBuild: TIGHTLIP_CHECK_BUILD
                optional: TIGHTLIP_CHECK_OPTIONAL?
                required: TIGHTLIP_CHECK_EMPTY
                absent: TIGHTLIP_CHECK_ABSENT
                """,
            envFile: "export TIGHTLIP_CHECK_FILE=file-value\n"
        )
        let evaluation = try #require(
            run.evaluate(processEnvironment: [
                "TIGHTLIP_CHECK_BUILD": "build-value",
                "TIGHTLIP_CHECK_OPTIONAL": "",
                "TIGHTLIP_CHECK_EMPTY": "",
            ]))
        #expect(evaluation.selection == .flat)
        #expect(!evaluation.succeeded)
        #expect(
            evaluation.variables.map { Row($0) } == [
                Row("TIGHTLIP_CHECK_FILE", .set, .envFile),
                Row("TIGHTLIP_CHECK_BUILD", .set, .buildEnvironment),
                Row("TIGHTLIP_CHECK_OPTIONAL", .setButEmptyAllowed, .buildEnvironment),
                Row("TIGHTLIP_CHECK_EMPTY", .setButEmpty, .buildEnvironment),
                Row("TIGHTLIP_CHECK_ABSENT", .missing, nil),
            ])

        let result = run.check(processEnvironment: [
            "TIGHTLIP_CHECK_BUILD": "build-value",
            "TIGHTLIP_CHECK_OPTIONAL": "",
            "TIGHTLIP_CHECK_EMPTY": "",
        ])
        #expect(!result.succeeded)
        for line in [
            "  TIGHTLIP_CHECK_FILE (Secrets.fromFile): set, from the env file",
            "  TIGHTLIP_CHECK_BUILD (Secrets.fromBuild): set, from the build environment",
            "  TIGHTLIP_CHECK_OPTIONAL (Secrets.optional): set but empty (allowed), from the build environment",
            "  TIGHTLIP_CHECK_EMPTY (Secrets.required): set but empty, from the build environment",
            "  TIGHTLIP_CHECK_ABSENT (Secrets.absent): missing",
            "result: a build would fail",
        ] {
            #expect(result.lines.contains(line), "missing \(line) in \(result.lines)")
        }
    }

    @Test func buildEnvironmentIsTheSourceWhenItOverridesTheFile() throws {
        let run = try ScratchTarget(
            config: "envFile: ./secrets.env\nkey: TIGHTLIP_CHECK_KEY",
            envFile: "export TIGHTLIP_CHECK_KEY=file-value\n"
        )
        let evaluation = try #require(run.evaluate(processEnvironment: ["TIGHTLIP_CHECK_KEY": "build-value"]))
        #expect(evaluation.variables.map { Row($0) } == [Row("TIGHTLIP_CHECK_KEY", .set, .buildEnvironment)])
    }

    @Test func passingConfigSaysABuildWouldSucceed() throws {
        let run = try ScratchTarget(config: "key: TIGHTLIP_CHECK_KEY")
        let result = run.check(processEnvironment: ["TIGHTLIP_CHECK_KEY": "v"])
        #expect(result.succeeded)
        #expect(result.lines.first == "Checking Demo (\(run.configURL.path))")
        #expect(result.lines.contains("environment: none (flat config)"))
        #expect(result.lines.last == "result: a build would succeed")
    }

    @Test func reportsTheEnvFileAndWhetherItExists() throws {
        let run = try ScratchTarget(config: "envFile: ./nowhere.env\nkey: TIGHTLIP_CHECK_KEY")
        let result = run.check(processEnvironment: ["TIGHTLIP_CHECK_KEY": "v"])
        let expected = run.directory.appendingPathComponent("nowhere.env").standardizedFileURL.path
        #expect(result.lines.contains("env file: \(expected) (not found)"), "output: \(result.lines)")

        let present = try ScratchTarget(config: "envFile: ./secrets.env\nkey: TIGHTLIP_CHECK_KEY", envFile: "")
        let presentPath = present.directory.appendingPathComponent("secrets.env").standardizedFileURL.path
        #expect(
            present.check(processEnvironment: ["TIGHTLIP_CHECK_KEY": "v"]).lines.contains("env file: \(presentPath)"))
    }

    // MARK: values never appear

    @Test(arguments: [
        ["TIGHTLIP_CHECK_A": "build-secret-A", "TIGHTLIP_CHECK_B": "build-secret-B"],
        ["TIGHTLIP_CHECK_A": "build-secret-A"],
        ["TIGHTLIP_CHECK_B": "", "TIGHTLIP_ENV": "staging"],
        ["TIGHTLIP_ENV": "production", "TIGHTLIP_CHECK_P": "prod-secret-P"],
    ])
    func neverPrintsAValue(processEnvironment: [String: String]) throws {
        // Flat and sectioned, passing and failing, with the file's values overridden
        // (the warning path) and not.
        let secretsInFile = [
            "TIGHTLIP_CHECK_A": "file-secret-A",
            "TIGHTLIP_CHECK_B": "file-secret-B",
            "TIGHTLIP_CHECK_P": "file-secret-P",
            "TIGHTLIP_CHECK_ALT": "file-secret-ALT",
        ]
        let envFile = secretsInFile.map { "export \($0.key)=\($0.value)\n" }.joined()
        let values = Set(secretsInFile.values).union(processEnvironment.values.filter { !$0.isEmpty })
            .subtracting(["staging", "production"])

        let flat = try ScratchTarget(
            config: "envFile: ./secrets.env\na: TIGHTLIP_CHECK_A\nb: TIGHTLIP_CHECK_B\nc: TIGHTLIP_CHECK_ALT",
            envFile: envFile
        )
        let sectioned = try ScratchTarget(
            config: """
                envFile: ./secrets.env
                staging:
                  a: TIGHTLIP_CHECK_A
                  b: TIGHTLIP_CHECK_B?
                production:
                  a: TIGHTLIP_CHECK_P
                  b: TIGHTLIP_CHECK_MISSING
                """,
            envFile: envFile
        )
        for run in [flat, sectioned] {
            let lines = run.check(processEnvironment: processEnvironment).lines
            #expect(lines.count > 3)
            for line in lines {
                for value in values {
                    #expect(!line.contains(value), "printed a value: \(line)")
                }
            }
        }
    }

    // MARK: section selection

    private static let inferable = """
        staging:
          key: TIGHTLIP_CHECK_STAGING
        production:
          key: TIGHTLIP_CHECK_PRODUCTION
        """

    @Test func tightlipEnvSelectionIsNamed() throws {
        let run = try ScratchTarget(config: Self.inferable)
        let environment = ["TIGHTLIP_ENV": "production", "TIGHTLIP_CHECK_PRODUCTION": "v"]
        let evaluation = try #require(run.evaluate(processEnvironment: environment))
        #expect(evaluation.selection == .selected(.tightlipEnv(section: "production")))
        #expect(run.check(processEnvironment: environment).lines.contains("environment: production (TIGHTLIP_ENV)"))
    }

    @Test func unsetConfigurationIsReportedAsUnset() throws {
        let run = try ScratchTarget(config: Self.inferable)
        let environment = ["TIGHTLIP_CHECK_STAGING": "v"]
        let evaluation = try #require(run.evaluate(processEnvironment: environment))
        #expect(
            evaluation.selection
                == .selected(
                    .inferred(
                        section: "staging", configuration: nil, debugSection: "staging", releaseSection: "production")
                ))
        let result = run.check(processEnvironment: environment)
        #expect(result.succeeded)
        #expect(
            result.lines.contains(
                "environment: staging (CONFIGURATION is unset, which infers the same section as Debug; "
                    + "Debug selects 'staging', Release selects 'production')"
            ), "output: \(result.lines)")
    }

    @Test(arguments: [("Debug", "staging"), ("Release", "production"), ("release", "production")])
    func configurationInferenceNamesTheConfiguration(configuration: String, section: String) throws {
        let run = try ScratchTarget(config: Self.inferable)
        let environment = [
            "CONFIGURATION": configuration,
            "TIGHTLIP_CHECK_STAGING": "v",
            "TIGHTLIP_CHECK_PRODUCTION": "v",
        ]
        let evaluation = try #require(run.evaluate(processEnvironment: environment))
        #expect(evaluation.selection.section == section)
        #expect(
            run.check(processEnvironment: environment).lines.contains(
                "environment: \(section) (inferred from CONFIGURATION=\(configuration); "
                    + "Debug selects 'staging', Release selects 'production')"
            ))
    }

    @Test(arguments: [
        (["CONFIGURATION": "AppStore"], "CONFIGURATION='AppStore' is neither 'Debug' nor 'Release'"),
        (["TIGHTLIP_ENV": "qa"], "TIGHTLIP_ENV='qa' does not match any section"),
    ])
    func undeterminedSectionSaysWhy(environment: [String: String], reason: String) throws {
        let run = try ScratchTarget(config: Self.inferable)
        let evaluation = try #require(run.evaluate(processEnvironment: environment))
        guard case .undetermined(let error) = evaluation.selection else {
            Issue.record("expected undetermined, got \(evaluation.selection)")
            return
        }
        #expect(error.message.contains(reason))
        #expect(evaluation.variables.isEmpty)
        #expect(!evaluation.succeeded)

        let result = run.check(processEnvironment: environment)
        #expect(!result.succeeded)
        #expect(result.lines.contains { $0.hasPrefix("error: cannot determine environment: \(reason)") })
        #expect(result.lines.contains { $0.hasPrefix("environment: cannot determine (\(reason)") })
        #expect(result.lines.last == "result: a build would fail")
    }

    @Test func threeSectionsWithoutTightlipEnvCannotBeDetermined() throws {
        let run = try ScratchTarget(config: "a:\n  key: K_A\nb:\n  key: K_B\nc:\n  key: K_C")
        let result = run.check(processEnvironment: [:])
        #expect(!result.succeeded)
        #expect(
            result.lines.contains(
                "environment: cannot determine (TIGHTLIP_ENV is not set and automatic inference is not possible)"))
    }

    // MARK: config errors

    @Test func parseErrorKeepsThePathLineForm() throws {
        let run = try ScratchTarget(config: "key: TIGHTLIP_CHECK_KEY\nbad line")
        let result = run.check(processEnvironment: ["TIGHTLIP_CHECK_KEY": "v"])
        #expect(!result.succeeded)
        #expect(result.lines.contains { $0.hasPrefix("\(run.configURL.path):2: error: ") }, "output: \(result.lines)")
        #expect(result.lines.last == "result: a build would fail")
        #expect(run.evaluate(processEnvironment: [:]) == nil)
    }

    @Test func missingConfigFails() throws {
        let run = try ScratchTarget(config: nil)
        let result = run.check(processEnvironment: [:])
        #expect(!result.succeeded)
        #expect(result.lines.contains { $0.hasPrefix("error: Tightlip config missing at ") })
        #expect(result.lines.last == "result: a build would fail")
    }

    // MARK: parity with the build

    @Test(arguments: [
        ("key: TIGHTLIP_CHECK_KEY", ["TIGHTLIP_CHECK_KEY": "v"]),
        ("key: TIGHTLIP_CHECK_KEY", ["TIGHTLIP_CHECK_KEY": ""]),
        ("key: TIGHTLIP_CHECK_KEY?", ["TIGHTLIP_CHECK_KEY": ""]),
        ("key: TIGHTLIP_CHECK_KEY", [:]),
        ("key: TIGHTLIP_CHECK_KEY\n\tbad: X", ["TIGHTLIP_CHECK_KEY": "v"]),
        (inferable, ["TIGHTLIP_CHECK_STAGING": "v"]),
        (inferable, ["TIGHTLIP_CHECK_STAGING": "v", "CONFIGURATION": "Release"]),
        (inferable, ["TIGHTLIP_CHECK_STAGING": "v", "CONFIGURATION": "Beta"]),
        (inferable, ["TIGHTLIP_ENV": "production", "TIGHTLIP_CHECK_PRODUCTION": "v"]),
    ])
    func failsExactlyWhenTheBuildFails(config: String, environment: [String: String]) throws {
        let run = try ScratchTarget(config: config)
        let build = run.generate(processEnvironment: environment)
        let result = run.check(processEnvironment: environment)
        #expect(result.succeeded == build.succeeded)
        // The check prints everything the build does, then its report.
        #expect(Array(result.lines.dropFirst().prefix(build.lines.count)) == build.lines)
    }

    // MARK: helpers

    private struct Row: Equatable, CustomStringConvertible {
        let envVar: String
        let state: VariableStatus.State
        let source: VariableStatus.Source?

        init(_ envVar: String, _ state: VariableStatus.State, _ source: VariableStatus.Source?) {
            self.envVar = envVar
            self.state = state
            self.source = source
        }

        init(_ status: VariableStatus) {
            self.init(status.secret.envVar, status.state, status.source)
        }

        var description: String { "\(envVar) \(state) \(source.map { "\($0)" } ?? "-")" }
    }
}
