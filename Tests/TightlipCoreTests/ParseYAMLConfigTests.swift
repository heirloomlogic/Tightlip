import Testing
import TightlipCore

@Suite("parseYAMLConfig — flat format")
struct ParseYAMLConfigFlatTests {
    // MARK: Happy path

    @Test func parsesSingleMapping() throws {
        let result = try parseFlat("revenueCatAPIKey: APP_RC", path: "t.yml")
        #expect(result == [ParsedSecret(name: "revenueCatAPIKey", envVar: "APP_RC")])
    }

    @Test func parsesMultipleMappingsInSourceOrder() throws {
        let text = """
            beta: B
            alpha: A
            """
        let result = try parseFlat(text, path: "t.yml")
        #expect(result.map(\.name) == ["beta", "alpha"])
    }

    @Test func skipsBlankLines() throws {
        let text = "\n\nfoo: BAR\n\n"
        let result = try parseFlat(text, path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func skipsCommentLines() throws {
        let text = """
            # header comment
            # another
            foo: BAR
            # trailing
            """
        let result = try parseFlat(text, path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func handlesCRLFLineEndings() throws {
        let text = "foo: BAR\r\nbaz: QUX\r\n"
        let result = try parseFlat(text, path: "t.yml")
        #expect(result.map(\.name) == ["foo", "baz"])
        #expect(result.map(\.envVar) == ["BAR", "QUX"])
    }

    @Test func allowsZeroSpacesAfterColon() throws {
        let result = try parseFlat("foo:BAR", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func allowsMultipleSpacesAfterColon() throws {
        let result = try parseFlat("foo:     BAR", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func trimsTrailingSpacesOnValue() throws {
        let result = try parseFlat("foo: BAR    ", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func allowsDigitsAfterFirstCharInIdentifiers() throws {
        let result = try parseFlat("apiKeyV2: APP_V2_KEY", path: "t.yml")
        #expect(result == [ParsedSecret(name: "apiKeyV2", envVar: "APP_V2_KEY")])
    }

    @Test func allowsUnderscoreStartingIdentifiers() throws {
        let result = try parseFlat("_k: _E", path: "t.yml")
        #expect(result == [ParsedSecret(name: "_k", envVar: "_E")])
    }

    // MARK: Errors

    @Test func emptyFileIsParseError() {
        expectParseError("", line: nil, reasonContains: "no secrets")
    }

    @Test func onlyCommentsIsParseError() {
        expectParseError("# just a comment\n# another\n", line: nil, reasonContains: "no secrets")
    }

    @Test func tabIndentIsParseErrorOnLine1() {
        expectParseError("\tfoo: BAR", line: 1, reasonContains: "indentation")
    }

    @Test func spaceIndentIsParseErrorOnLine1() {
        expectParseError("  foo: BAR", line: 1, reasonContains: "indentation")
    }

    @Test func nbspIndentIsParseErrorOnLine1() {
        expectParseError("\u{00A0}foo: BAR", line: 1, reasonContains: "U+00A0 NO-BREAK SPACE at column 1")
    }

    @Test func nbspBetweenColonAndValueIsNamedWithItsColumn() {
        // Pasted from a chat app, this line looks exactly like `foo: BAR`; the error
        // must say what is actually wrong instead of echoing the line back.
        expectParseError("foo:\u{00A0}BAR", line: 1, reasonContains: "U+00A0 NO-BREAK SPACE at column 5")
    }

    @Test func zeroWidthSpaceIsParseError() {
        expectParseError("foo: BAR\nbar:\u{200B} BAZ", line: 2, reasonContains: "U+200B")
    }

    @Test func carriageReturnOnlyLineEndingsAreNamed() {
        expectParseError("foo: A\rbar: B", line: 1, reasonContains: "carriage return")
    }

    @Test func invisibleCharactersInCommentsAndBlankLinesAreAllowed() throws {
        let result = try parseFlat("# note\u{00A0}with nbsp\n\u{00A0}\nfoo: BAR", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func tabBetweenColonAndValueIsParseError() {
        expectParseError("foo:\tBAR", line: 1, reasonContains: "tab")
    }

    @Test func duplicateKeyIsParseErrorReferencingFirstLine() {
        let text = """
            foo: A
            bar: B
            foo: C
            """
        expectParseError(text, line: 3, reasonContains: "duplicate")
        expectParseError(text, line: 3, reasonContains: "line 1")
    }

    @Test func missingValueIsParseError() {
        // "foo:" alone is now detected as a section header (sectioned format).
        // The error becomes "section 'foo' has no secrets" rather than a flat-format
        // parse error. Verify it still errors.
        expectParseError("foo:", line: 1, reasonContains: "no secrets")
    }

    @Test func missingColonIsParseError() {
        expectParseError("foo BAR", line: 1, reasonContains: "expected")
    }

    @Test func multipleValueWordsIsParseError() {
        expectParseError("foo: BAR BAZ", line: 1, reasonContains: "expected")
    }

    @Test func quotedValueIsParseError() {
        expectParseError(#"foo: "BAR""#, line: 1, reasonContains: "expected")
    }

    @Test func inlineCommentIsParseError() {
        expectParseError("foo: BAR # inline", line: 1, reasonContains: "expected")
    }

    @Test func digitStartingKeyIsParseError() {
        expectParseError("1foo: BAR", line: 1, reasonContains: "expected")
    }

    @Test func hyphenInKeyIsParseError() {
        expectParseError("foo-bar: BAR", line: 1, reasonContains: "expected")
    }

    @Test func nonAsciiIdentifierIsParseError() {
        expectParseError("café: BAR", line: 1, reasonContains: "expected")
    }

    @Test(arguments: ["class", "default", "func", "static", "import", "true", "Self"])
    func swiftKeywordAsSecretNameIsParseError(keyword: String) {
        expectParseError("\(keyword): APP_VALUE", line: 1, reasonContains: "Swift keyword")
    }

    @Test(arguments: ["salt", "decode", "Swift", "Foundation"])
    func generatedHelperNameAsSecretNameIsParseError(name: String) {
        expectParseError("\(name): APP_VALUE", line: 1, reasonContains: "reserved")
    }

    @Test(arguments: ["Type", "Protocol", "_"])
    func restrictedMemberNameAsSecretNameIsParseError(name: String) {
        // Swift forbids type members named `Type`/`Protocol` (metatype syntax) and
        // `_` binds nothing — all three compile-break the generated file.
        expectParseError("\(name): APP_VALUE", line: 1, reasonContains: "member")
    }

    @Test(arguments: ["Data", "String", "UInt8", "UTF8", "fatalError", "open"])
    func namesTheShimNoLongerCollidesWithAreAllowed(name: String) throws {
        // The shim spells library symbols module-qualified, so these compile as members
        // (GeneratedCodeIntegrationTests proves it); `open` is a contextual keyword.
        let result = try parseFlat("\(name): APP_VALUE", path: "t.yml")
        #expect(result == [ParsedSecret(name: name, envVar: "APP_VALUE")])
    }

    @Test func swiftKeywordAsEnvVarNameIsAllowed() throws {
        // Only the property name is emitted as a Swift identifier; the env var
        // side never appears in generated code.
        let result = try parseFlat("apiKey: class", path: "t.yml")
        #expect(result == [ParsedSecret(name: "apiKey", envVar: "class")])
    }

    @Test func errorLineNumberPointsAtOffendingLine() {
        expectParseError("foo: BAR\n\tbad: VAL", line: 2, reasonContains: "indentation")
    }

    @Test func parsePathAppearsInFormattedMessage() {
        do {
            _ = try parseYAMLConfig("", path: "Secrets.yml")
            Issue.record("expected throw")
        } catch {
            #expect(error.message.hasPrefix("Secrets.yml"))
        }
    }

    @Test func parseDiagnosticUsesXcodeAttributableForm() {
        // `path:line: error: reason` is what Xcode turns into a clickable issue on the
        // offending line; `error: path:line: reason` renders as unattributed text.
        do {
            _ = try parseYAMLConfig("foo: BAR\n\tbad: X", path: "/p/Secrets.yml")
            Issue.record("expected throw")
        } catch {
            #expect(error.diagnostic.hasPrefix("/p/Secrets.yml:2: error: "))
        }
        do {
            _ = try parseYAMLConfig("", path: "/p/Secrets.yml")
            Issue.record("expected throw")
        } catch {
            #expect(error.diagnostic == "/p/Secrets.yml: error: no secrets declared")
        }
    }

    @Test func nonParseDiagnosticsKeepTheErrorPrefix() {
        let error = ConfigError.missingEnvironmentVariable(envVar: "K", property: "Secrets.k")
        #expect(error.diagnostic == "error: environment variable K must be set to generate Secrets.k")
    }

    @Test func parseLineAppearsInFormattedMessage() {
        do {
            _ = try parseYAMLConfig("foo: BAR\n\tbad: X", path: "cfg.yml")
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("cfg.yml:2:"))
        }
    }

    // MARK: Helpers

    /// Parses `text` and unwraps the flat result, failing the test on a sectioned config.
    private func parseFlat(_ text: String, path: String) throws -> [ParsedSecret] {
        guard case .flat(let secrets) = try parseYAMLConfig(text, path: path) else {
            Issue.record("expected flat config")
            return []
        }
        return secrets
    }

    private func expectParseError(
        _ text: String,
        path: String = "t.yml",
        line expectedLine: Int?,
        reasonContains substring: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try parseYAMLConfig(text, path: path)
            Issue.record("expected ConfigError.parse", sourceLocation: sourceLocation)
        } catch {
            guard case .parse(_, let actualLine, let reason) = error else {
                Issue.record("expected .parse, got \(error)", sourceLocation: sourceLocation)
                return
            }
            #expect(
                actualLine == expectedLine,
                "got line \(String(describing: actualLine)); reason was: \(reason)",
                sourceLocation: sourceLocation
            )
            #expect(reason.contains(substring), "reason was: \(reason)", sourceLocation: sourceLocation)
        }
    }
}
