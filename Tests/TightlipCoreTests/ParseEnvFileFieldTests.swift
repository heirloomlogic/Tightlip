import Foundation
import Testing
import TightlipCore

@Suite("parseYAMLConfigFile — envFile directive")
struct ParseEnvFileFieldTests {
    @Test func absentDirectiveYieldsNilEnvFile() throws {
        let result = try parseYAMLConfigFile("foo: BAR", path: "t.yml")
        #expect(result.envFile == nil)
        #expect(result.secrets == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))
    }

    @Test func capturesTildePath() throws {
        let text = """
            envFile: ~/.zshenv
            foo: BAR
            """
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.envFile == "~/.zshenv")
        #expect(result.secrets == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))
    }

    @Test func capturesAbsolutePath() throws {
        let text = """
            envFile: /etc/secrets.env
            foo: BAR
            """
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.envFile == "/etc/secrets.env")
    }

    @Test func capturesRelativePath() throws {
        let text = """
            envFile: ../shared.env
            foo: BAR
            """
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.envFile == "../shared.env")
    }

    @Test func directiveBeforeSectionedConfig() throws {
        let text = """
            envFile: ~/.bash_profile
            staging:
              apiKey: STAGING_KEY
            prod:
              apiKey: PROD_KEY
            """
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.envFile == "~/.bash_profile")
        guard case .sectioned(let sections) = result.secrets else {
            Issue.record("expected sectioned")
            return
        }
        #expect(sections.count == 2)
    }

    @Test func directiveAcceptsCommentsAbove() throws {
        let text = """
            # comment before directive
            # another

            envFile: ~/.zshenv
            foo: BAR
            """
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.envFile == "~/.zshenv")
    }

    @Test func directiveAfterContentIsNotCaptured() throws {
        let text = """
            foo: BAR
            envFile: ~/.zshenv
            """
        // 'envFile' becomes a duplicate-style flat property attempt; the value ~/.zshenv
        // is not a valid identifier under the existing grammar.
        do {
            _ = try parseYAMLConfigFile(text, path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            #expect(error.message.contains("expected"))
        }
    }

    @Test func emptyDirectiveValueIsParseError() throws {
        do {
            _ = try parseYAMLConfigFile("envFile:\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            guard case .parse(_, let line, let reason) = error else {
                Issue.record("expected .parse, got \(error)")
                return
            }
            #expect(line == 1)
            #expect(reason.contains("envFile"))
        }
    }

    @Test func tabInDirectiveLineIsParseError() throws {
        do {
            _ = try parseYAMLConfigFile("envFile:\t~/.zshenv\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            #expect(error.message.contains("tab"))
        }
    }

    @Test func inlineCommentInDirectiveIsParseError() throws {
        // Without this, "# local" becomes part of the path, fileExists fails, and
        // sourcing silently falls back to the process environment.
        do {
            _ = try parseYAMLConfigFile("envFile: ./secrets.env # local\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            guard case .parse(_, let line, let reason) = error else {
                Issue.record("expected .parse, got \(error)")
                return
            }
            #expect(line == 1)
            #expect(reason.contains("envFile"))
        }
    }

    @Test func spaceInDirectivePathIsParseError() throws {
        do {
            _ = try parseYAMLConfigFile("envFile: ~/My Files/env\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            #expect(error.message.contains("envFile"))
        }
    }

    @Test func bareIdentifierDirectiveValueIsParseError() throws {
        // `envFile: SOME_VAR` on the first line is ambiguous with a secret mapping;
        // refuse it and point at the ./ spelling for genuine relative paths.
        do {
            _ = try parseYAMLConfigFile("envFile: SOME_VAR\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            #expect(error.message.contains("./"))
        }
    }

    @Test(arguments: [
        ("~", "not a directory"),
        ("./configs/", "not a directory"),
        ("\"./x.env\"", "written bare"),
        ("'./x.env'", "written bare"),
        ("$HOME/x.env", "written bare"),
        ("`pwd`/x.env", "written bare"),
        ("~root/x.env", "'~user'"),
    ])
    func unusableDirectiveValueIsParseError(value: String, reasonContains: String) throws {
        // Each of these would otherwise resolve to a directory (sourced as a silent
        // no-op) or to a literal path that never exists.
        do {
            _ = try parseYAMLConfigFile("envFile: \(value)\nfoo: BAR", path: "t.yml")
            Issue.record("expected parse error for \(value)")
        } catch {
            guard case .parse(_, let line, let reason) = error else {
                Issue.record("expected .parse, got \(error)")
                return
            }
            #expect(line == 1)
            #expect(reason.contains(reasonContains), "reason was: \(reason)")
        }
    }

    @Test func envFileAsSecretNameIsParseError() throws {
        // Only the first meaningful line is directive position; anywhere else,
        // `envFile` as a property name is reserved to keep the config unambiguous.
        do {
            _ = try parseYAMLConfigFile("foo: BAR\nenvFile: BAZ", path: "t.yml")
            Issue.record("expected parse error")
        } catch {
            guard case .parse(_, let line, let reason) = error else {
                Issue.record("expected .parse, got \(error)")
                return
            }
            #expect(line == 2)
            #expect(reason.contains("reserved"))
        }
    }

    @Test func parseYAMLConfigDiscardsDirective() throws {
        let text = """
            envFile: ~/.zshenv
            foo: BAR
            """
        let parsed = try parseYAMLConfig(text, path: "t.yml")
        #expect(parsed == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))
    }

    // MARK: resolveEnvFilePath

    @Test func resolveEnvFilePathExpandsTilde() {
        let home = URL(fileURLWithPath: "/Users/test")
        let result = resolveEnvFilePath(
            "~/.zshenv",
            configDir: URL(fileURLWithPath: "/anything"),
            homeDirectory: home
        )
        #expect(result.path == "/Users/test/.zshenv")
    }

    @Test func resolveEnvFilePathHandlesAbsolutePath() {
        let result = resolveEnvFilePath(
            "/etc/secrets.env",
            configDir: URL(fileURLWithPath: "/wherever"),
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        #expect(result.path == "/etc/secrets.env")
    }

    @Test func resolveEnvFilePathHandlesRelativePath() {
        let configDir = URL(fileURLWithPath: "/Users/test/proj/Target")
        let result = resolveEnvFilePath(
            "../shared.env",
            configDir: configDir,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        // Standardized, so the plugin's input tracking and the tool agree on one path.
        #expect(result.path == "/Users/test/proj/shared.env")
    }

    @Test func resolveEnvFilePathCollapsesDoubledSlashes() {
        let result = resolveEnvFilePath(
            "~//.zshenv",
            configDir: URL(fileURLWithPath: "/x"),
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        #expect(result.path == "/Users/test/.zshenv")
    }
}
