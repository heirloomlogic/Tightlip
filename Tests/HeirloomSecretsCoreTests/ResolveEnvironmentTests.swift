import HeirloomSecretsCore
import Testing

@Suite("resolveEnvironment")
struct ResolveEnvironmentTests {
    private let twoSections: [(name: String, secrets: [ParsedSecret])] = [
        (name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
        (name: "production", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    private let twoSectionsProd: [(name: String, secrets: [ParsedSecret])] = [
        (name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        (name: "prod", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    private let threeSections: [(name: String, secrets: [ParsedSecret])] = [
        (name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
        (name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        (name: "production", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    // MARK: HEIRLOOM_ENV takes priority

    @Test func heirloomEnvOverridesEverything() throws {
        let env = ["HEIRLOOM_ENV": "staging", "CONFIGURATION": "Release"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "staging")
    }

    @Test func heirloomEnvWorksWithThreeSections() throws {
        let env = ["HEIRLOOM_ENV": "qa"]
        let result = try resolveEnvironment(sections: threeSections, environment: env)
        #expect(result == "qa")
    }

    @Test func heirloomEnvMustMatchSection() {
        let env = ["HEIRLOOM_ENV": "nonexistent"]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: twoSections, environment: env)
        }
    }

    @Test func heirloomEnvErrorShowsAvailableSections() {
        let env = ["HEIRLOOM_ENV": "bad"]
        do {
            _ = try resolveEnvironment(sections: twoSections, environment: env)
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("staging"))
            #expect(error.message.contains("production"))
        }
    }

    @Test func emptyHeirloomEnvIsIgnored() throws {
        let env = ["HEIRLOOM_ENV": "", "CONFIGURATION": "Release"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "production")
    }

    // MARK: CONFIGURATION fallback — "production" section name

    @Test func releaseConfigurationSelectsProduction() throws {
        let env = ["CONFIGURATION": "Release"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "production")
    }

    @Test func debugConfigurationSelectsNonProduction() throws {
        let env = ["CONFIGURATION": "Debug"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "staging")
    }

    @Test func noConfigurationDefaultsToNonProduction() throws {
        let result = try resolveEnvironment(sections: twoSections, environment: [:])
        #expect(result == "staging")
    }

    // MARK: CONFIGURATION fallback — "prod" section name

    @Test func releaseSelectsProd() throws {
        let env = ["CONFIGURATION": "Release"]
        let result = try resolveEnvironment(sections: twoSectionsProd, environment: env)
        #expect(result == "prod")
    }

    @Test func debugSelectsNonProd() throws {
        let env = ["CONFIGURATION": "Debug"]
        let result = try resolveEnvironment(sections: twoSectionsProd, environment: env)
        #expect(result == "qa")
    }

    @Test func configurationIsCaseInsensitive() throws {
        let env = ["CONFIGURATION": "release"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "production")
    }

    // MARK: Indeterminate cases

    @Test func threeSectionsWithoutHeirloomEnvFails() {
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: threeSections, environment: [:])
        }
    }

    @Test func twoSectionsWithoutProdNameFails() {
        let sections: [(name: String, secrets: [ParsedSecret])] = [
            (name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
            (name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        ]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: sections, environment: [:])
        }
    }

    @Test func indeterminateErrorSuggestsHeirloomEnv() {
        do {
            _ = try resolveEnvironment(sections: threeSections, environment: [:])
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("HEIRLOOM_ENV"))
        }
    }
}
