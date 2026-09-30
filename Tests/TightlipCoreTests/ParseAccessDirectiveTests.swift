import Testing
import TightlipCore

@Suite("parseYAMLConfigFile — access directive")
struct ParseAccessDirectiveTests {
    @Test func absentDirectiveDefaultsToInternal() throws {
        let result = try parseYAMLConfigFile("foo: BAR", path: "t.yml")
        #expect(result.access == .internal)
    }

    @Test(arguments: [
        ("internal", AccessLevel.internal),
        ("package", AccessLevel.package),
        ("public", AccessLevel.public),
    ])
    func acceptsEachLevel(value: String, expected: AccessLevel) throws {
        let result = try parseYAMLConfigFile("access: \(value)\nfoo: BAR", path: "t.yml")
        #expect(result.access == expected)
        #expect(result.envFile == nil)
        #expect(result.secrets == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))
    }

    @Test func toleratesSurroundingSpacesAndCommentsAbove() throws {
        let text = "# comment before directive\n\naccess:   public  \nfoo: BAR"
        let result = try parseYAMLConfigFile(text, path: "t.yml")
        #expect(result.access == .public)
    }

    @Test(arguments: ["public?", "private", "fileprivate", "open", "Public", "PUBLIC", "public # shared"])
    func rejectsAnyOtherValue(value: String) {
        expectParseError(
            "# header\naccess: \(value)\nfoo: BAR",
            line: 2,
            reasonContains: "access must be internal, package, or public; got '\(value)'"
        )
    }

    @Test(arguments: ["ACCESS_TOKEN", "ACCESS_TOKEN?", "private"])
    func identifierValueExplainsThatAccessIsReserved(value: String) {
        // A pre-2.0 config may open with a secret named `access`; `access: ACCESS_TOKEN`
        // reads as a mapping, so the error says the name is reserved and needs renaming.
        expectParseError(
            "access: \(value)\nfoo: BAR",
            line: 1,
            reasonContains: "'access' is reserved as a directive; rename the secret"
        )
    }

    @Test(arguments: ["public # shared", "~/x", "a b"])
    func nonIdentifierValueKeepsThePlainError(value: String) {
        do {
            _ = try parseYAMLConfigFile("access: \(value)\nfoo: BAR", path: "t.yml")
            Issue.record("expected ConfigError.parse")
        } catch {
            #expect(error.message.contains("access must be internal, package, or public"))
            #expect(!error.message.contains("rename the secret"), "message was: \(error.message)")
        }
    }

    @Test func emptyValueIsParseError() {
        expectParseError("access:\nfoo: BAR", line: 1, reasonContains: "access directive has no value")
    }

    @Test func tabInDirectiveLineIsParseError() {
        expectParseError("access:\tpublic\nfoo: BAR", line: 1, reasonContains: "tab")
    }

    // MARK: directive order

    @Test(arguments: [
        "access: public\nenvFile: ~/.zshenv\n",
        "envFile: ~/.zshenv\naccess: public\n",
        "envFile: ~/.zshenv\n# comments and blank lines between directives are fine\n\naccess: public\n",
    ])
    func eitherOrder(header: String) throws {
        let flat = try parseYAMLConfigFile(header + "foo: BAR", path: "t.yml")
        #expect(flat.access == .public)
        #expect(flat.envFile == "~/.zshenv")
        #expect(flat.secrets == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))

        let sectioned = try parseYAMLConfigFile(
            header + "staging:\n  apiKey: STAGING_KEY\nprod:\n  apiKey: PROD_KEY", path: "t.yml")
        #expect(sectioned.access == .public)
        #expect(sectioned.envFile == "~/.zshenv")
        guard case .sectioned(let sections) = sectioned.secrets else {
            Issue.record("expected sectioned")
            return
        }
        #expect(sections.map(\.name) == ["staging", "prod"])
    }

    @Test func errorLineNumbersBelowTheHeaderStayCorrect() {
        expectParseError(
            "access: public\nenvFile: ./x.env\nfoo: BAR\nfoo: BAZ",
            line: 4,
            reasonContains: "duplicate key 'foo' (first defined on line 3)"
        )
    }

    @Test(arguments: [
        ("access: public\naccess: package\nfoo: BAR", "access", 2),
        ("access: public\nenvFile: ./a.env\naccess: public\nfoo: BAR", "access", 3),
        ("envFile: ./a.env\naccess: public\nenvFile: ./b.env\nfoo: BAR", "envFile", 3),
    ])
    func duplicateDirectiveIsParseError(text: String, directive: String, line: Int) {
        expectParseError(
            text, line: line, reasonContains: "duplicate \(directive) directive (first defined on line 1)")
    }

    // MARK: position and reservation

    @Test(arguments: ["foo: BAR\naccess: public", "foo: BAR\naccess: ACCESS_TOKEN", "staging:\n  access: ACCESS_TOKEN"])
    func accessIsReservedAsASecretName(text: String) {
        expectParseError(text, line: 2, reasonContains: "'access' is reserved for the access directive")
    }

    @Test func accessAfterASectionIsParseError() {
        expectParseError("staging:\n  k: V\naccess: public", line: 3, reasonContains: "expected section header")
    }

    @Test func namesThatOnlyStartWithAccessAreOrdinarySecrets() throws {
        let result = try parseYAMLConfigFile("accessToken: ACCESS_TOKEN", path: "t.yml")
        #expect(result.access == .internal)
        #expect(result.secrets == .flat([ParsedSecret(name: "accessToken", envVar: "ACCESS_TOKEN")]))
    }

    @Test func parseYAMLConfigDiscardsDirective() throws {
        let parsed = try parseYAMLConfig("access: public\nfoo: BAR", path: "t.yml")
        #expect(parsed == .flat([ParsedSecret(name: "foo", envVar: "BAR")]))
    }
}
