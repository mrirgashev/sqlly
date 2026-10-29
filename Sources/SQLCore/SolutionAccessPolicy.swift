import Foundation
import CryptoKit

/// Derives access to a coding exercise's worked solution from persisted history.
///
/// Ten different unsuccessful graded code submissions are required. Successes,
/// conceptual assessments, service failures and unclassified legacy attempts do
/// not contribute. Passing an exercise never bypasses the ten-failure rule.
/// This policy does not execute SQL or decide whether an answer is correct.
public struct SolutionAccessPolicy: Equatable, Sendable {
    public static let requiredDistinctFailures = 10
    /// Matches the practice engine's editor limit and bounds fingerprint work.
    public static let maximumCodeBytes = 131_072

    public let distinctFailedCodeAttempts: Int
    public var remainingAttempts: Int { max(0, Self.requiredDistinctFailures - distinctFailedCodeAttempts) }
    public var isUnlocked: Bool { distinctFailedCodeAttempts >= Self.requiredDistinctFailures }

    public init(exerciseID: String, attempts: [Attempt]) {
        // Persisted UUIDs are unique. Defensive handling of repeated imported
        // input is order-independent: conflicting copies cannot award credit.
        var byID: [UUID: Attempt] = [:]
        var conflictingIDs: Set<UUID> = []
        for attempt in attempts {
            if let existing = byID[attempt.id] {
                if existing.exerciseID != attempt.exerciseID || existing.passed != attempt.passed
                    || existing.submissionKind != attempt.submissionKind
                    || !existing.sql.utf8.elementsEqual(attempt.sql.utf8) {
                    conflictingIDs.insert(attempt.id)
                }
            } else { byID[attempt.id] = attempt }
        }
        var fingerprints: Set<String> = []
        for attempt in byID.values where attempt.exerciseID == exerciseID && !attempt.passed
            && attempt.submissionKind == .gradedCode && !conflictingIDs.contains(attempt.id) {
            if let fingerprint = Self.codeFingerprint(attempt.sql) { fingerprints.insert(fingerprint) }
        }
        distinctFailedCodeAttempts = fingerprints.count
    }

    /// A deterministic source fingerprint, never a comparison with an answer.
    ///
    /// SQL token spacing, comments, ASCII unquoted case and empty statements are
    /// ignored. Quoted payloads remain byte-exact; dollar-quote tag names are
    /// delimiters, not part of the value. This follows PostgreSQL 18 lexical
    /// quoting and the bundled UTF-8/C engine's ASCII identifier case folding.
    /// E-string escapes, doubled quotes and nested comments are recognized.
    /// Plain strings use PostgreSQL's default standard_conforming_strings=on;
    /// no session settings or procedural string bodies are evaluated here.
    /// https://www.postgresql.org/docs/18/sql-syntax-lexical.html
    /// Returns nil for blank/comment-only/empty-statement input or oversized code.
    public static func codeFingerprint(_ sql: String) -> String? {
        guard sql.utf8.count <= maximumCodeBytes else { return nil }
        var lexer = AttemptCodeLexer(bytes: Array(sql.utf8))
        guard let payload = lexer.canonicalPayload() else { return nil }
        return SHA256.hash(data: Data(payload)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A bounded lexical scan for source uniqueness, independent of SQL grading.
private struct AttemptCodeLexer {
    let bytes: [UInt8]
    private var index = 0
    private var tokens: [Token] = []
    private struct Token {
        let kind: UInt8
        let payload: [UInt8]
    }

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func canonicalPayload() -> [UInt8]? {
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isWhitespace(byte) { index += 1; continue }
            if matches(45, 45) { skipLineComment(); continue }
            if matches(47, 42) { skipBlockComment(); continue }

            if byte == 59 {
                // Empty commands and an optional final terminator are formatting.
                if !tokens.isEmpty && tokens.last?.kind != 59 { tokens.append(Token(kind: 59, payload: [])) }
                index += 1; continue
            }
            if byte == 39 || byte == 34 {
                tokens.append(Token(kind: byte, payload: quoted(delimiter: byte, escapeBackslashes: false)))
                continue
            }
            if isPrefixedQuote() {
                let prefixStart = index
                let unicode = Self.foldASCII(bytes[index]) == 117
                index += unicode ? 2 : 1
                let delimiter = bytes[index]
                let prefix = bytes[prefixStart..<index].map(Self.foldASCII)
                let content = quoted(delimiter: delimiter, escapeBackslashes: prefix == [101])
                tokens.append(Token(kind: delimiter, payload: prefix + content))
                continue
            }
            if byte == 36, let delimiterEnd = dollarDelimiterEnd() {
                let start = index
                let delimiter = Array(bytes[start...delimiterEnd])
                let bodyStart = delimiterEnd + 1
                if let closing = Data(bytes[bodyStart...]).range(of: Data(delimiter)) {
                    let bodyEnd = bodyStart + closing.lowerBound
                    tokens.append(Token(kind: 36, payload: Array(bytes[bodyStart..<bodyEnd])))
                    index = bodyStart + closing.upperBound
                } else {
                    // An unfinished quoted value is still a distinct code attempt;
                    // preserve its bytes instead of interpreting embedded comments.
                    tokens.append(Token(kind: 0, payload: Array(bytes[start...])))
                    index = bytes.count
                }
                continue
            }
            if Self.isAtom(byte) {
                let start = index
                let identifier = Self.isIdentifierStart(byte)
                index += 1
                while index < bytes.count && (Self.isAtom(bytes[index]) || (identifier && bytes[index] == 36)) { index += 1 }
                tokens.append(Token(kind: 1, payload: bytes[start..<index].map(Self.foldASCII)))
                continue
            }
            if Self.isOperator(byte) {
                let start = index
                index += 1
                while index < bytes.count && Self.isOperator(bytes[index]) && !matches(45, 45) && !matches(47, 42) { index += 1 }
                // PostgreSQL splits trailing +/- off standard operator runs,
                // so `a+-b` and `a + - b` retain the same token boundaries.
                if !bytes[start..<index].contains(where: Self.isNonstandardOperator) {
                    while index > start + 1 && [43, 45].contains(bytes[index - 1]) { index -= 1 }
                }
                tokens.append(Token(kind: 2, payload: Array(bytes[start..<index])))
                continue
            }
            if byte == 58 && index + 1 < bytes.count && bytes[index + 1] == 58 {
                tokens.append(Token(kind: 3, payload: [58, 58])); index += 2
                continue
            }
            tokens.append(Token(kind: 3, payload: [byte])); index += 1
        }
        if tokens.last?.kind == 59 { tokens.removeLast() }
        guard !tokens.isEmpty else { return nil }
        var payload: [UInt8] = []
        for token in tokens {
            payload.append(token.kind)
            let length = UInt32(token.payload.count)
            payload += [UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]
            payload += token.payload
        }
        return payload
    }

    private func matches(_ first: UInt8, _ second: UInt8) -> Bool {
        index + 1 < bytes.count && bytes[index] == first && bytes[index + 1] == second
    }

    private mutating func skipLineComment() {
        index += 2
        while index < bytes.count && bytes[index] != 10 && bytes[index] != 13 { index += 1 }
    }

    private mutating func skipBlockComment() {
        index += 2
        var depth = 1
        while index < bytes.count && depth > 0 {
            if matches(47, 42) { depth += 1; index += 2 }
            else if matches(42, 47) { depth -= 1; index += 2 }
            else { index += 1 }
        }
    }

    private mutating func quoted(delimiter: UInt8, escapeBackslashes: Bool) -> [UInt8] {
        let start = index
        index += 1
        while index < bytes.count {
            if escapeBackslashes && bytes[index] == 92 {
                index += min(2, bytes.count - index)
            } else if bytes[index] == delimiter {
                index += 1
                if index < bytes.count && bytes[index] == delimiter { index += 1 }
                else { break }
            } else { index += 1 }
        }
        return Array(bytes[start..<index])
    }

    private func isPrefixedQuote() -> Bool {
        guard index + 1 < bytes.count else { return false }
        let first = Self.foldASCII(bytes[index])
        if [101, 98, 120, 110].contains(first) && bytes[index + 1] == 39 { return true }
        return first == 117 && index + 2 < bytes.count && bytes[index + 1] == 38
            && [39, 34].contains(bytes[index + 2])
    }

    private func dollarDelimiterEnd() -> Int? {
        var cursor = index + 1
        guard cursor < bytes.count else { return nil }
        if bytes[cursor] == 36 { return cursor }
        guard Self.isIdentifierStart(bytes[cursor]) else { return nil }
        cursor += 1
        while cursor < bytes.count && Self.isAtom(bytes[cursor]) { cursor += 1 }
        return cursor < bytes.count && bytes[cursor] == 36 ? cursor : nil
    }

    private static func foldASCII(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
    private static func isWhitespace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
    private static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte >= 128
    }
    private static func isAtom(_ byte: UInt8) -> Bool { isIdentifierStart(byte) || (48...57).contains(byte) }
    private static func isOperator(_ byte: UInt8) -> Bool { [43, 45, 42, 47, 60, 62, 61, 126, 33, 64, 35, 37, 94, 38, 124, 96, 63].contains(byte) }
    private static func isNonstandardOperator(_ byte: UInt8) -> Bool { [126, 33, 64, 35, 37, 94, 38, 124, 96, 63].contains(byte) }
}
