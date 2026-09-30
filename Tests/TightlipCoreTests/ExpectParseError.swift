import Testing
import TightlipCore

/// Parses `text` and expects a ``ConfigError/parse(path:line:reason:)`` on `line` whose
/// reason contains `substring`. Failures point at the caller.
func expectParseError(
    _ text: String,
    path: String = "t.yml",
    line expectedLine: Int?,
    reasonContains substring: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        _ = try parseYAMLConfigFile(text, path: path)
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
