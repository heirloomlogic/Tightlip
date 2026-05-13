import Testing
import TightlipCore

@Suite("encodeSwiftLiteral")
struct EncodeSwiftLiteralTests {
    @Test func wrapsPlainAsciiInDoubleQuotes() {
        #expect(encodeSwiftLiteral("hello") == "\"hello\"")
    }

    @Test func handlesEmptyString() {
        #expect(encodeSwiftLiteral("") == "\"\"")
    }

    @Test func escapesBackslash() {
        #expect(encodeSwiftLiteral("a\\b") == "\"a\\\\b\"")
    }

    @Test func escapesDoubleQuote() {
        #expect(encodeSwiftLiteral("a\"b") == "\"a\\\"b\"")
    }

    @Test func escapesNewline() {
        #expect(encodeSwiftLiteral("a\nb") == "\"a\\nb\"")
    }

    @Test func escapesCarriageReturn() {
        #expect(encodeSwiftLiteral("a\rb") == "\"a\\rb\"")
    }

    @Test func escapesTab() {
        #expect(encodeSwiftLiteral("a\tb") == "\"a\\tb\"")
    }

    @Test func escapesNul() {
        #expect(encodeSwiftLiteral("a\0b") == "\"a\\0b\"")
    }

    @Test func escapesLowControlCharAsUnicode() {
        #expect(encodeSwiftLiteral("\u{01}") == "\"\\u{1}\"")
    }

    @Test func escapesDeleteAsUnicode() {
        #expect(encodeSwiftLiteral("\u{7F}") == "\"\\u{7F}\"")
    }

    @Test func passesForwardSlashUnchanged() {
        #expect(encodeSwiftLiteral("a/b") == "\"a/b\"")
    }

    @Test func passesUnicodeAboveAsciiThrough() {
        #expect(encodeSwiftLiteral("café") == "\"café\"")
        #expect(encodeSwiftLiteral("🔑") == "\"🔑\"")
    }

    @Test func escapesMixedContent() {
        #expect(encodeSwiftLiteral("say \"hi\"\nbye") == "\"say \\\"hi\\\"\\nbye\"")
    }
}
