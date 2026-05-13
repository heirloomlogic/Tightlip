import Testing
import TightlipCore

@Suite("parseYAMLConfig — flat format")
struct ParseYAMLConfigFlatTests {
    // MARK: Happy path

    @Test func parsesSingleMapping() throws {
        let result = try parseFlatYAMLConfig("revenueCatAPIKey: APP_RC", path: "t.yml")
        #expect(result == [ParsedSecret(name: "revenueCatAPIKey", envVar: "APP_RC")])
    }

    @Test func parsesMultipleMappingsInSourceOrder() throws {
        let text = """
            beta: B
            alpha: A
            """
        let result = try parseFlatYAMLConfig(text, path: "t.yml")
        #expect(result.map(\.name) == ["beta", "alpha"])
    }

    @Test func skipsBlankLines() throws {
        let text = "\n\nfoo: BAR\n\n"
        let result = try parseFlatYAMLConfig(text, path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func skipsCommentLines() throws {
        let text = """
            # header comment
            # another
            foo: BAR
            # trailing
            """
        let result = try parseFlatYAMLConfig(text, path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func handlesCRLFLineEndings() throws {
        let text = "foo: BAR\r\nbaz: QUX\r\n"
        let result = try parseFlatYAMLConfig(text, path: "t.yml")
        #expect(result.map(\.name) == ["foo", "baz"])
        #expect(result.map(\.envVar) == ["BAR", "QUX"])
    }

    @Test func allowsZeroSpacesAfterColon() throws {
        let result = try parseFlatYAMLConfig("foo:BAR", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func allowsMultipleSpacesAfterColon() throws {
        let result = try parseFlatYAMLConfig("foo:     BAR", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func trimsTrailingSpacesOnValue() throws {
        let result = try parseFlatYAMLConfig("foo: BAR    ", path: "t.yml")
        #expect(result == [ParsedSecret(name: "foo", envVar: "BAR")])
    }

    @Test func allowsDigitsAfterFirstCharInIdentifiers() throws {
        let result = try parseFlatYAMLConfig("apiKeyV2: APP_V2_KEY", path: "t.yml")
        #expect(result == [ParsedSecret(name: "apiKeyV2", envVar: "APP_V2_KEY")])
    }

    @Test func allowsUnderscoreStartingIdentifiers() throws {
        let result = try parseFlatYAMLConfig("_k: _E", path: "t.yml")
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
        expectParseError("\u{00A0}foo: BAR", line: 1, reasonContains: "indentation")
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
        expectParseError("foo:", line: nil, reasonContains: "no secrets")
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

    @Test func parseLineAppearsInFormattedMessage() {
        do {
            _ = try parseYAMLConfig("foo: BAR\n\tbad: X", path: "cfg.yml")
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("cfg.yml:2:"))
        }
    }

    // MARK: Helper

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
