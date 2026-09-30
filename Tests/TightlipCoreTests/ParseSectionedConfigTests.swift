import Testing
import TightlipCore

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

    @Test func questionMarkSuffixAppliesPerSection() throws {
        // Staging may allow an empty analytics key while production requires one.
        let text = """
            staging:
              analyticsKey: STAGING_ANALYTICS_KEY?
            production:
              analyticsKey: PROD_ANALYTICS_KEY
            """
        guard case .sectioned(let sections) = try parseYAMLConfig(text, path: "t.yml") else {
            Issue.record("expected .sectioned")
            return
        }
        #expect(
            sections[0].secrets == [
                ParsedSecret(name: "analyticsKey", envVar: "STAGING_ANALYTICS_KEY", allowsEmpty: true)
            ])
        #expect(sections[1].secrets == [ParsedSecret(name: "analyticsKey", envVar: "PROD_ANALYTICS_KEY")])
    }

    // MARK: Errors

    @Test func misplacedQuestionMarkInSectionIsError() {
        expectParseError("staging:\n  k: S_KEY ?", line: 2, reasonContains: "expected")
    }

    @Test func mismatchedSectionKeysIsError() {
        let text = """
            staging:
              apiKey: S_KEY
              extra: S_EXTRA
            prod:
              apiKey: P_KEY
            """
        expectParseError(text, line: 4, reasonContains: "differs from")
    }

    @Test func mismatchedSectionKeysReportsMissingKey() {
        let text = """
            staging:
              apiKey: S_KEY
              extra: S_EXTRA
            prod:
              apiKey: P_KEY
            """
        expectParseError(text, line: 4, reasonContains: "missing extra")
    }

    @Test func mismatchedSectionKeysReportsUnexpectedKey() {
        let text = """
            staging:
              apiKey: S_KEY
            prod:
              apiKey: P_KEY
              bonus: P_BONUS
            """
        expectParseError(text, line: 3, reasonContains: "unexpected bonus")
    }

    @Test func duplicateSectionNameIsError() {
        let text = """
            staging:
              key: A
            staging:
              key: B
            """
        expectParseError(text, line: 3, reasonContains: "duplicate section 'staging' (first defined on line 1)")
    }

    @Test func emptySectionIsError() {
        let text = """
            staging:
            prod:
              key: P
            """
        // Points at the empty section's own header, not the next one.
        expectParseError(text, line: 1, reasonContains: "no secrets")
    }

    @Test func emptyLastSectionPointsAtItsHeader() {
        let text = "staging:\n  key: S\n\nprod:\n"
        expectParseError(text, line: 4, reasonContains: "section 'prod' has no secrets")
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

    @Test func swiftKeywordAsSecretNameInSectionIsError() {
        let text = "staging:\n  default: STAGING_DEFAULT"
        expectParseError(text, line: 2, reasonContains: "Swift keyword")
    }

    @Test func generatedHelperNameAsSecretNameInSectionIsError() {
        let text = "staging:\n  decode: STAGING_DECODE"
        expectParseError(text, line: 2, reasonContains: "reserved")
    }

    @Test func swiftKeywordAsSectionNameIsAllowed() throws {
        // Section names never appear as Swift identifiers in generated code —
        // only in the environment-name comment — so keywords are fine here.
        let text = "default:\n  key: D_KEY\nprod:\n  key: P_KEY"
        let config = try parseYAMLConfig(text, path: "t.yml")
        guard case .sectioned(let sections) = config else {
            Issue.record("expected .sectioned")
            return
        }
        #expect(sections.map(\.name) == ["default", "prod"])
    }
}
