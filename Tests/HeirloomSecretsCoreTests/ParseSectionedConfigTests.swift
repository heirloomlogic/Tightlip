import HeirloomSecretsCore
import Testing

@Suite("parseYAMLConfig — sectioned format")
struct ParseSectionedConfigTests {
    // MARK: Happy path

    @Test func parsesTwoSections() throws {
        let text = """
            staging:
              apiKey: STAGING_KEY
              baseURL: STAGING_URL
            production:
              apiKey: PROD_KEY
              baseURL: PROD_URL
            """
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .sectioned(let sections) = config else {
            Issue.record("expected .sectioned")
            return
        }
        #expect(sections.count == 2)
        #expect(sections[0].name == "staging")
        #expect(
            sections[0].secrets == [
                ParsedSecret(name: "apiKey", envVar: "STAGING_KEY"),
                ParsedSecret(name: "baseURL", envVar: "STAGING_URL"),
            ])
        #expect(sections[1].name == "production")
        #expect(
            sections[1].secrets == [
                ParsedSecret(name: "apiKey", envVar: "PROD_KEY"),
                ParsedSecret(name: "baseURL", envVar: "PROD_URL"),
            ])
    }

    @Test func parsesWithCommentsBetweenSections() throws {
        let text = """
            # Dev environment
            staging:
              key: S_KEY

            # Production environment
            prod:
              key: P_KEY
            """
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .sectioned(let sections) = config else {
            Issue.record("expected .sectioned")
            return
        }
        #expect(sections.count == 2)
        #expect(sections[0].name == "staging")
        #expect(sections[1].name == "prod")
    }

    @Test func parsesWithBlankLinesBetweenSections() throws {
        let text = """
            qa:
              key: QA_KEY

            prod:
              key: PROD_KEY
            """
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .sectioned(let sections) = config else {
            Issue.record("expected .sectioned")
            return
        }
        #expect(sections[0].name == "qa")
        #expect(sections[1].name == "prod")
    }

    @Test func detectsSectionedFormatFromFirstLine() throws {
        let text = "staging:\n  key: K\nprod:\n  key: P"
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .sectioned = config else {
            Issue.record("expected .sectioned")
            return
        }
    }

    @Test func detectsFlatFormatFromFirstLine() throws {
        let text = "key: ENV_VAR"
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .flat = config else {
            Issue.record("expected .flat")
            return
        }
    }

    // MARK: Errors

    @Test func mismatchedSectionKeysIsError() {
        let text = """
            staging:
              apiKey: S_KEY
              extra: S_EXTRA
            prod:
              apiKey: P_KEY
            """
        expectParseError(text, line: nil, reasonContains: "differs from")
    }

    @Test func mismatchedSectionKeysReportsMissingKey() {
        let text = """
            staging:
              apiKey: S_KEY
              extra: S_EXTRA
            prod:
              apiKey: P_KEY
            """
        expectParseError(text, line: nil, reasonContains: "missing extra")
    }

    @Test func mismatchedSectionKeysReportsUnexpectedKey() {
        let text = """
            staging:
              apiKey: S_KEY
            prod:
              apiKey: P_KEY
              bonus: P_BONUS
            """
        expectParseError(text, line: nil, reasonContains: "unexpected bonus")
    }

    @Test func duplicateSectionNameIsError() {
        let text = """
            staging:
              key: A
            staging:
              key: B
            """
        expectParseError(text, line: 3, reasonContains: "duplicate section")
    }

    @Test func emptySectionIsError() {
        let text = """
            staging:
            prod:
              key: P
            """
        expectParseError(text, line: 2, reasonContains: "no secrets")
    }

    @Test func wrongIndentIsError() {
        let text = "staging:\n    key: K"
        expectParseError(text, line: 2, reasonContains: "2-space indent")
    }

    @Test func tabIndentInSectionIsError() {
        let text = "staging:\n\tkey: K"
        expectParseError(text, line: 2, reasonContains: "tab")
    }

    @Test func flatLineAfterSectionHeaderIsError() {
        let text = "staging:\nkey: K"
        expectParseError(text, line: 2, reasonContains: "section header")
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
