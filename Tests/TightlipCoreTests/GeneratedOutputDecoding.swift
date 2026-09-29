import Foundation

/// Extracts the base64 ciphertext for a property and decodes it using the salt embedded
/// in the same generated output. Mirrors the runtime decode shim emitted by
/// ``renderSecretsEnum(_:environment:)``.
func decodeGeneratedProperty(_ out: String, propertyName: String) throws -> String {
    let salt = try parseSalt(from: out)
    let needle = "static let \(propertyName): Swift.String = Self.decode(\""
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

func parseSalt(from out: String) throws -> [UInt8] {
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
