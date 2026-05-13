import Foundation
import Testing
import TightlipCore

@Suite("renderSecretsEnum — obfuscation")
struct ObfuscatedRenderTests {
    @Test func roundtripsAsciiValue() throws {
        let value = "sk_test_1234567890ABCDEF"
        let out = renderSecretsEnum([(name: "apiKey", value: value)])
        let decoded = try decodeFromOutput(out, propertyName: "apiKey")
        #expect(decoded == value)
    }

    @Test func roundtripsValueWithSpecialChars() throws {
        let value = #"line1\n"with quotes"\nand\\backslashes"#
        let out = renderSecretsEnum([(name: "weird", value: value)])
        let decoded = try decodeFromOutput(out, propertyName: "weird")
        #expect(decoded == value)
    }

    @Test func roundtripsUTF8MultiByteValue() throws {
        let value = "café — naïve résumé 🎉"
        let out = renderSecretsEnum([(name: "name", value: value)])
        let decoded = try decodeFromOutput(out, propertyName: "name")
        #expect(decoded == value)
    }

    @Test func roundtripsEmptyValue() throws {
        let out = renderSecretsEnum([(name: "blank", value: "")])
        let decoded = try decodeFromOutput(out, propertyName: "blank")
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
            let decoded = try decodeFromOutput(out, propertyName: name)
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

    // MARK: helpers

    /// Extracts the base64 ciphertext for a property and decodes it using the salt embedded
    /// in the same generated output. Mirrors the runtime decode shim emitted by
    /// ``renderSecretsEnum(_:environment:)``.
    private func decodeFromOutput(_ out: String, propertyName: String) throws -> String {
        let salt = try parseSalt(from: out)
        let needle = "static let \(propertyName): String = Self.decode(\""
        guard let range = out.range(of: needle) else {
            throw Failure.propertyNotFound(propertyName)
        }
        let after = out[range.upperBound...]
        guard let endQuote = after.firstIndex(of: "\"") else {
            throw Failure.malformedDecodeCall
        }
        let base64 = String(after[after.startIndex..<endQuote])
        guard let data = Data(base64Encoded: base64) else {
            throw Failure.invalidBase64
        }
        var bytes = [UInt8](data)
        for i in bytes.indices { bytes[i] ^= salt[i % salt.count] }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func parseSalt(from out: String) throws -> [UInt8] {
        guard let line = out.split(separator: "\n").first(where: { $0.contains("private static let salt:") }) else {
            throw Failure.saltLineMissing
        }
        let parts = line.components(separatedBy: "0x").dropFirst()
        let bytes: [UInt8] = try parts.map { piece in
            let hex = piece.prefix(2)
            guard let byte = UInt8(hex, radix: 16) else {
                throw Failure.badHexByte(String(hex))
            }
            return byte
        }
        guard bytes.count == 32 else { throw Failure.wrongSaltLength(bytes.count) }
        return bytes
    }

    private enum Failure: Error {
        case propertyNotFound(String)
        case malformedDecodeCall
        case invalidBase64
        case saltLineMissing
        case wrongSaltLength(Int)
        case badHexByte(String)
    }
}
