import Testing
import TightlipCore

@Suite("missingEnvVarDiagnostic")
struct MissingEnvVarDiagnosticTests {
    @Test func listsVarsSharingThePrefixSorted() {
        let note = missingEnvVarDiagnostic(
            envVar: "ACME_API_KEY",
            environment: ["ACME_OTHER": "x", "ACME_THING": "y", "PATH": "/usr/bin"]
        )
        #expect(note.contains("2 env var(s) with prefix 'ACME_'"))
        #expect(note.contains("[ACME_OTHER, ACME_THING]"))
        #expect(note.contains("total env count = 3"))
    }

    @Test func reportsZeroWhenNothingMatches() {
        let note = missingEnvVarDiagnostic(envVar: "ACME_API_KEY", environment: ["PATH": "/usr/bin"])
        #expect(note.contains("0 env var(s) with prefix 'ACME_'"))
        #expect(note.contains("[]"))
    }

    @Test func leadingUnderscoreStaysInThePrefix() {
        let note = missingEnvVarDiagnostic(
            envVar: "_ACME_KEY",
            environment: ["_ACME_KEY2": "x", "ACME_OTHER": "y"]
        )
        #expect(note.contains("prefix '_ACME_'"))
        #expect(note.contains("[_ACME_KEY2]"))
    }

    @Test func handlesEnvVarWithoutUnderscore() {
        let note = missingEnvVarDiagnostic(envVar: "APIKEY", environment: ["APIKEY_SIBLING": "x"])
        #expect(note.contains("prefix 'APIKEY_'"))
        #expect(note.contains("[APIKEY_SIBLING]"))
    }
}
