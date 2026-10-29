import Foundation

public struct Grade: Sendable {
    public let passed: Bool
    public let message: String
    public let fixturesPassed: Int
    public let fixturesTotal: Int
    public let result: QueryResult?
}

/// A PostgreSQL failure attributable to the submitted answer. Infrastructure,
/// fixture, and reference-answer failures retain their original error types.
public struct GradingSubmissionError: LocalizedError, Sendable {
    public let underlying: PostgresError
    public var message: String { underlying.message }
    public var sqlState: String { underlying.sqlState }
    public var errorDescription: String? { underlying.errorDescription }
    public init(_ underlying: PostgresError) { self.underlying = underlying }
}

/// Compares typed PostgreSQL results; preserves NULLs and bag multiplicity.
/// Numeric types compare exact decimal values, without rounding tolerances.
public enum ResultComparator {
    private static let numericOIDs: Set<UInt32> = [20, 21, 23, 26, 700, 701, 1700]

    private static func normalized(_ value: String?, oid: UInt32) -> String {
        guard let value else { return "N" }
        if numericOIDs.contains(oid), let number = canonicalNumber(value) { return "D" + number }
        if oid == 3802 { return "J" + canonicalJSONB(value) }
        return "S" + value
    }

    // PostgreSQL already emits JSONB objects in canonical key order. Normalize
    // only unquoted number tokens so NUMERIC scale inside state snapshots does
    // not reject equivalent values. Quoted strings and array order stay exact.
    private static func canonicalJSONB(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        var quoted = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if quoted {
                output.append(byte); index += 1
                if byte == 92, index < bytes.count { output.append(bytes[index]); index += 1 }
                else if byte == 34 { quoted = false }
            } else if byte == 34 {
                quoted = true; output.append(byte); index += 1
            } else if byte == 45 || (48...57).contains(byte) {
                let start = index
                index += 1
                while index < bytes.count, (48...57).contains(bytes[index]) || [43, 45, 46, 69, 101].contains(bytes[index]) { index += 1 }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                output.append(contentsOf: (canonicalNumber(token) ?? token).utf8)
            } else {
                if ![9, 10, 13, 32].contains(byte) { output.append(byte) }
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    // PostgreSQL NUMERIC can exceed Foundation.Decimal's precision. Normalize
    // its decimal text without ever converting to a bounded numeric type.
    private static func canonicalNumber(_ value: String) -> String? {
        var text = value.lowercased()
        var negative = false
        if text.first == "-" { negative = true; text.removeFirst() }
        else if text.first == "+" { text.removeFirst() }
        let pieces = text.split(separator: "e", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let mantissa = pieces.first else { return nil }
        let exponent: Int
        if pieces.count == 2 { guard let parsed = Int(pieces[1]), parsed > -1_000_000, parsed < 1_000_000 else { return nil }; exponent = parsed }
        else { exponent = 0 }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        var digits = parts.joined()
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        var scale = (parts.count == 2 ? parts[1].count : 0) - exponent
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0" }
        while digits.last == "0" { digits.removeLast(); scale -= 1 }
        return (negative ? "-" : "") + digits + "e" + String(-scale)
    }

    private static func key(_ row: [String?], columns: [QueryColumn]) -> String {
        row.enumerated().map { i, value in
            let s = normalized(value, oid: columns.indices.contains(i) ? columns[i].typeOID : 0)
            return "\(s.utf8.count):\(s)"
        }.joined()
    }

    public static func compare(actual: QueryResult, expected: QueryResult, ordered: Bool, columnNames: Bool, language: CourseLanguage = .english) -> String? {
        guard actual.columns.count == expected.columns.count else {
            return CoreText.format("Expected %ld columns, but your query returned %ld. Check the SELECT list.", language: language, expected.columns.count, actual.columns.count)
        }
        if columnNames, actual.columns.map(\.name) != expected.columns.map(\.name) {
            return CoreText.format("Column names must be %@. Check your aliases and column order.", language: language, expected.columns.map(\.name).joined(separator: ", "))
        }
        guard actual.rows.count == expected.rows.count else {
            return CoreText.format("Expected %ld rows, but your query returned %ld. Check filters, JOIN cardinality, and duplicates.", language: language, expected.rows.count, actual.rows.count)
        }
        let actualKeys = actual.rows.map { key($0, columns: actual.columns) }
        let expectedKeys = expected.rows.map { key($0, columns: expected.columns) }
        if ordered {
            guard actualKeys == expectedKeys else { return CoreText.text("Some values or their order differ. Check ORDER BY, NULL handling, expressions, and tie breakers.", language: language) }
        } else {
            guard actualKeys.sorted() == expectedKeys.sorted() else { return CoreText.text("Some values differ. Duplicate rows count separately. Check NULL handling, calculations, and JOIN conditions.", language: language) }
        }
        return nil
    }
}

public struct GradingService: Sendable {
    public let engine: PostgresEngine
    public init(engine: PostgresEngine) { self.engine = engine }

    public func grade(sql: String, exercise: Exercise, curriculum: Curriculum, language: CourseLanguage = .english) async throws -> Grade {
        var first: QueryResult?
        for index in exercise.fixtureIDs.indices {
            let fixture = curriculum.fixture(for: exercise, index: index)
            let actual: QueryResult
            let expected: QueryResult
            if let verification = exercise.validationSQL, !verification.isEmpty {
                // Check the authored reference and validation contract first.
                // Only a candidate's failure after this succeeds is attributable
                // to learner SQL (for example, dropping a required table).
                let reference = try await engine.validateDetailed(sql: exercise.solutionSQL, fixture: fixture, verificationSQL: verification)
                let submitted: ValidatedExecution
                do { submitted = try await engine.validateDetailed(sql: sql, fixture: fixture, verificationSQL: verification) }
                catch { throw Self.submissionError(error) }
                actual = submitted.state; expected = reference.state
                if first == nil { first = submitted.output }
                if exercise.checkOutput == true,
                   let issue = ResultComparator.compare(actual: submitted.output, expected: reference.output, ordered: exercise.outputOrdered ?? false, columnNames: exercise.columnNames, language: language) {
                    return Grade(passed: false, message: CoreText.format("%@ Fixture %ld of %ld.", language: language, issue, index + 1, exercise.fixtureIDs.count), fixturesPassed: index, fixturesTotal: exercise.fixtureIDs.count, result: first)
                }
            } else {
                do { actual = try await engine.execute(sql: sql, fixture: fixture) }
                catch { throw Self.submissionError(error) }
                expected = try await engine.execute(sql: exercise.solutionSQL, fixture: fixture)
            }
            if first == nil { first = actual }
            if let issue = ResultComparator.compare(actual: actual, expected: expected, ordered: exercise.ordered, columnNames: exercise.columnNames, language: language) {
                return Grade(passed: false, message: CoreText.format("%@ Fixture %ld of %ld.", language: language, issue, index + 1, exercise.fixtureIDs.count), fixturesPassed: index, fixturesTotal: exercise.fixtureIDs.count, result: first)
            }
        }
        let ordering = CoreText.text(exercise.ordered ? "Row order was checked." : "Equivalent row orderings are accepted.", language: language)
        return Grade(passed: true, message: CoreText.format("Correct across all %ld datasets. %@", language: language, exercise.fixtureIDs.count, ordering), fixturesPassed: exercise.fixtureIDs.count, fixturesTotal: exercise.fixtureIDs.count, result: first)
    }

    private static func submissionError(_ error: Error) -> Error {
        guard let postgres = error as? PostgresError, isSubmissionFailure(postgres) else { return error }
        return GradingSubmissionError(postgres)
    }

    static func isSubmissionFailure(_ error: PostgresError) -> Bool {
        guard error.origin == .submittedStatement || error.origin == .validation,
              !error.sqlState.isEmpty else { return false }
        let state = error.sqlState.uppercased()
        // SQLSTATE classes for transport, resource exhaustion, system/internal
        // failures and server shutdown must never count as an incorrect answer.
        if ["08", "53", "58", "XX"].contains(where: state.hasPrefix) { return false }
        if state.hasPrefix("57"), state != "57014" { return false }
        return true
    }

    /// Concept questions use explicit answer forms. SQL answers always use the
    /// execution-based grader above; no query text is compared with a reference.
    public func gradeResponse(_ response: String, exercise: Exercise, curriculum: Curriculum, language: CourseLanguage = .english) async throws -> Grade {
        if exercise.kind == "choose" {
            let chosen = Set((try? JSONDecoder().decode([String].self, from: Data(response.utf8))) ?? [])
            let passed = !chosen.isEmpty && chosen == Set(exercise.correctChoiceIDs ?? [])
            return Grade(passed: passed, message: CoreText.text(passed ? "Correct. You selected every valid option." : "Revisit the conditions. Select every valid option; more than one may be correct.", language: language), fixturesPassed: passed ? 1 : 0, fixturesTotal: 1, result: nil)
        }
        guard exercise.kind == "predict" else { throw ContentError.invalid(CoreText.text("Explanation tasks require learner self-assessment with the supplied rubric.", language: language)) }
        let rows: [[String?]]
        do { rows = try JSONDecoder().decode([[String?]].self, from: Data(response.utf8)) }
        catch { throw ContentError.invalid(CoreText.text("Enter values in the prediction table, or mark a missing value as NULL. Add or remove rows to match the predicted output.", language: language)) }
        var first: QueryResult?
        for index in exercise.fixtureIDs.indices {
            let expected = try await engine.execute(sql: exercise.solutionSQL, fixture: curriculum.fixture(for: exercise, index: index))
            if first == nil { first = expected }
            if rows.contains(where: { $0.count != expected.columns.count }) {
                return Grade(passed: false, message: CoreText.format("Each predicted row needs %ld values.", language: language, expected.columns.count), fixturesPassed: index, fixturesTotal: exercise.fixtureIDs.count, result: nil)
            }
            let predicted = QueryResult(columns: expected.columns, rows: rows, command: "Prediction", duration: 0)
            if let issue = ResultComparator.compare(actual: predicted, expected: expected, ordered: exercise.ordered, columnNames: false, language: language) {
                return Grade(passed: false, message: issue, fixturesPassed: index, fixturesTotal: exercise.fixtureIDs.count, result: nil)
            }
        }
        return Grade(passed: true, message: CoreText.format("Correct prediction, verified by PostgreSQL across all %ld datasets.", language: language, exercise.fixtureIDs.count), fixturesPassed: exercise.fixtureIDs.count, fixturesTotal: exercise.fixtureIDs.count, result: first)
    }
}
