import HeirloomSecretsCore
import Testing

@Suite("resolveSecret")
struct ResolveSecretTests {
    @Test func returnsEnvValueWhenSet() throws {
        let parsed = ParsedSecret(name: "revenueCatAPIKey", envVar: "FALLOW_RC")
        let resolved = try resolveSecret(parsed, environment: ["FALLOW_RC": "rc_abc"])
        #expect(resolved.name == "revenueCatAPIKey")
        #expect(resolved.value == "rc_abc")
    }

    @Test func preservesEmptyEnvValue() throws {
        let parsed = ParsedSecret(name: "k", envVar: "FOO")
        let resolved = try resolveSecret(parsed, environment: ["FOO": ""])
        #expect(resolved.value == "")
    }

    @Test func throwsWhenEnvVarMissing() {
        let parsed = ParsedSecret(name: "revenueCatAPIKey", envVar: "FALLOW_RC")
        #expect(
            throws: ConfigError.missingEnvironmentVariable(
                envVar: "FALLOW_RC",
                property: "Secrets.revenueCatAPIKey"
            )
        ) {
            _ = try resolveSecret(parsed, environment: [:])
        }
    }

    @Test func missingEnvVarErrorMessageMentionsVarAndProperty() {
        let err = ConfigError.missingEnvironmentVariable(
            envVar: "FALLOW_RC",
            property: "Secrets.revenueCatAPIKey"
        )
        #expect(err.message.contains("FALLOW_RC"))
        #expect(err.message.contains("Secrets.revenueCatAPIKey"))
    }
}
