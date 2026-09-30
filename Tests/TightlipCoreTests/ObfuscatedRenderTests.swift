import Foundation
import Testing
import TightlipCore

@Suite("renderSecretsEnum — obfuscation")
struct ObfuscatedRenderTests {
    @Test func roundtripsAsciiValue() throws {
        let value = "sk_test_1234567890ABCDEF"
        let out = renderSecretsEnum([(name: "apiKey", value: value)])
        let decoded = try decodeGeneratedProperty(out, propertyName: "apiKey")
        #expect(decoded == value)
    }

    @Test func roundtripsValueWithSpecialChars() throws {
        let value = #"line1\n"with quotes"\nand\\backslashes"#
        let out = renderSecretsEnum([(name: "weird", value: value)])
        let decoded = try decodeGeneratedProperty(out, propertyName: "weird")
        #expect(decoded == value)
    }

    @Test func roundtripsUTF8MultiByteValue() throws {
        let value = "café — naïve résumé 🎉"
        let out = renderSecretsEnum([(name: "name", value: value)])
        let decoded = try decodeGeneratedProperty(out, propertyName: "name")
        #expect(decoded == value)
    }

    @Test func roundtripsEmptyValue() throws {
        let out = renderSecretsEnum([(name: "blank", value: "")])
        let decoded = try decodeGeneratedProperty(out, propertyName: "blank")
        #expect(decoded == "")
    }

    @Test func roundtripsAllSecretsInMultiSecretEnum() throws {
        let pairs: [(name: String, value: String)] = [
            (name: "alpha", value: "AAA"),
            (name: "beta", value: "BBBBBB"),
            (name: "gamma", value: "Γγ - greek small letter gamma"),
        ]
        let out = renderSecretsEnum(pairs)
        for (name, value) in pairs {
            let decoded = try decodeGeneratedProperty(out, propertyName: name)
            #expect(decoded == value, "secret \(name) round-trip failed")
        }
    }

    @Test func sameInputsProduceByteIdenticalOutput() {
        let pairs = [(name: "a", value: "1"), (name: "b", value: "2")]
        let first = renderSecretsEnum(pairs)
        let second = renderSecretsEnum(pairs)
        #expect(first == second)
    }

    @Test func differentValuesYieldDifferentSalt() throws {
        let firstOut = renderSecretsEnum([(name: "k", value: "value1")])
        let secondOut = renderSecretsEnum([(name: "k", value: "value2")])
        let firstSalt = try parseSalt(from: firstOut)
        let secondSalt = try parseSalt(from: secondOut)
        #expect(firstSalt != secondSalt)
    }

    @Test func differentNamesYieldDifferentSalt() throws {
        let firstOut = renderSecretsEnum([(name: "alpha", value: "same")])
        let secondOut = renderSecretsEnum([(name: "beta", value: "same")])
        let firstSalt = try parseSalt(from: firstOut)
        let secondSalt = try parseSalt(from: secondOut)
        #expect(firstSalt != secondSalt)
    }

    @Test func plaintextValueDoesNotAppearInOutput() {
        let value = "PLAINTEXT_SHOULD_BE_HIDDEN_12345"
        let out = renderSecretsEnum([(name: "k", value: value)])
        #expect(!out.contains(value))
    }
}
