import Testing
import TightlipCore

@Suite("resolveEnvironment")
struct ResolveEnvironmentTests {
    private let twoSections: [ParsedSection] = [
        ParsedSection(name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
        ParsedSection(name: "production", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    private let twoSectionsProd: [ParsedSection] = [
        ParsedSection(name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        ParsedSection(name: "prod", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    private let threeSections: [ParsedSection] = [
        ParsedSection(name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
        ParsedSection(name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        ParsedSection(name: "production", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
    ]

    // MARK: TIGHTLIP_ENV takes priority

    @Test func tightlipEnvOverridesEverything() throws {
        let env = ["TIGHTLIP_ENV": "staging", "CONFIGURATION": "Release"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "staging")
    }

    @Test func tightlipEnvWorksWithThreeSections() throws {
        let env = ["TIGHTLIP_ENV": "qa"]
        let result = try resolveEnvironment(sections: threeSections, environment: env)
        #expect(result == "qa")
    }

    @Test func tightlipEnvMustMatchSection() {
        let env = ["TIGHTLIP_ENV": "nonexistent"]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: twoSections, environment: env)
        }
    }

    @Test func tightlipEnvErrorShowsAvailableSections() {
        let env = ["TIGHTLIP_ENV": "bad"]
        do {
            _ = try resolveEnvironment(sections: twoSections, environment: env)
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("staging"))
            #expect(error.message.contains("production"))
        }
    }

    @Test func emptyTightlipEnvIsIgnored() throws {
        let env = ["TIGHTLIP_ENV": "", "CONFIGURATION": "Release"]
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

    // MARK: Custom configuration names refuse to guess

    @Test(arguments: ["AppStore", "Beta", "AppStore-Release", "Staging"])
    func unknownConfigurationNameRefusesToInfer(configuration: String) {
        // Guessing non-production for a custom Release-like configuration would
        // ship staging keys in a release archive — the worst silent outcome.
        let env = ["CONFIGURATION": configuration]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: twoSections, environment: env)
        }
    }

    @Test func unknownConfigurationErrorNamesTheConfiguration() {
        do {
            _ = try resolveEnvironment(
                sections: twoSections,
                environment: ["CONFIGURATION": "AppStore"]
            )
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("AppStore"))
            #expect(error.message.contains("TIGHTLIP_ENV"))
        }
    }

    @Test func tightlipEnvOverridesUnknownConfiguration() throws {
        let env = ["TIGHTLIP_ENV": "production", "CONFIGURATION": "AppStore"]
        let result = try resolveEnvironment(sections: twoSections, environment: env)
        #expect(result == "production")
    }

    // MARK: Indeterminate cases

    @Test func threeSectionsWithoutTightlipEnvFails() {
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: threeSections, environment: [:])
        }
    }

    @Test func twoSectionsWithoutProdNameFails() {
        let sections: [ParsedSection] = [
            ParsedSection(name: "staging", secrets: [ParsedSecret(name: "key", envVar: "S_KEY")]),
            ParsedSection(name: "qa", secrets: [ParsedSecret(name: "key", envVar: "Q_KEY")]),
        ]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: sections, environment: [:])
        }
    }

    @Test func bothProdNamesWithoutTightlipEnvFails() {
        // With sections `prod` and `production`, inference would treat `prod`
        // as the production section and `production` as the *other* one —
        // mapping Debug builds to "production". Refuse to guess.
        let sections: [ParsedSection] = [
            ParsedSection(name: "prod", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
            ParsedSection(name: "production", secrets: [ParsedSecret(name: "key", envVar: "PP_KEY")]),
        ]
        #expect(throws: ConfigError.self) {
            _ = try resolveEnvironment(sections: sections, environment: ["CONFIGURATION": "Debug"])
        }
    }

    @Test func bothProdNamesStillResolveViaTightlipEnv() throws {
        let sections: [ParsedSection] = [
            ParsedSection(name: "prod", secrets: [ParsedSecret(name: "key", envVar: "P_KEY")]),
            ParsedSection(name: "production", secrets: [ParsedSecret(name: "key", envVar: "PP_KEY")]),
        ]
        let result = try resolveEnvironment(
            sections: sections,
            environment: ["TIGHTLIP_ENV": "production"]
        )
        #expect(result == "production")
    }

    @Test func indeterminateErrorSuggestsTightlipEnv() {
        do {
            _ = try resolveEnvironment(sections: threeSections, environment: [:])
            Issue.record("expected throw")
        } catch {
            #expect(error.message.contains("TIGHTLIP_ENV"))
        }
    }
}
