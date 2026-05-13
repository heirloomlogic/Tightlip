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
        // appendingPathComponent doesn't collapse '..'; just verify it's relative-joined.
        #expect(result.path.hasPrefix("/Users/test/proj/Target/"))
        #expect(result.path.hasSuffix("shared.env"))
    }

    @Test func resolveEnvFilePathBareTilde() {
        let home = URL(fileURLWithPath: "/Users/test")
        let result = resolveEnvFilePath(
            "~",
            configDir: URL(fileURLWithPath: "/x"),
            homeDirectory: home
        )
        #expect(result.path == "/Users/test")
    }
}
