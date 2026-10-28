import Foundation
import Testing
@testable import SQLCore

@Suite(.serialized)
struct MutationContractTests {
    @Test func returningOutputAndCommittedStateAreBothCheckedWithoutDoubleMutation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-Returning-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let course = Curriculum(title: "Test", version: "1", postgresVersion: "18.6", fixtures: [
            "a": "CREATE TABLE counter(n integer); INSERT INTO counter VALUES(0);",
            "b": "CREATE TABLE counter(n integer); INSERT INTO counter VALUES(10);"
        ], modules: [])
        var exercise = Exercise(id: "returning", title: "Return the change", prompt: "", difficulty: "Intermediate", kind: "modify", starterSQL: "", solutionSQL: "UPDATE counter SET n=n+1 RETURNING n", fixtureIDs: ["a", "b"], ordered: true, columnNames: true, hints: ["Use RETURNING"], explanation: "", validationSQL: "SELECT n FROM counter")
        exercise.checkOutput = true
        do {
            let one = try await engine.validateDetailed(sql: exercise.solutionSQL, fixture: course.fixtures["a"]!, verificationSQL: "SELECT n FROM counter")
            #expect(one.output.rows == [["1"]])
            #expect(one.state.rows == [["1"]])
            let grader = GradingService(engine: engine)
            let missing = try await grader.grade(sql: "UPDATE counter SET n=n+1", exercise: exercise, curriculum: course)
            #expect(!missing.passed)
            let incorrect = try await grader.grade(sql: "UPDATE counter SET n=n+1 RETURNING n+1 AS n", exercise: exercise, curriculum: course)
            #expect(!incorrect.passed)
            let equivalent = try await grader.grade(sql: "UPDATE counter AS c SET n=c.n+1 RETURNING c.n::bigint AS n", exercise: exercise, curriculum: course)
            #expect(equivalent.passed && equivalent.fixturesPassed == 2)
            await engine.shutdown(); try? FileManager.default.removeItem(at: base)
        } catch { await engine.shutdown(); try? FileManager.default.removeItem(at: base); throw error }
    }

    @Test func strengthenedContentChecksRejectHiddenDestructiveChangesAndFakeSequences() async throws {
        let course = try Curriculum.load()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-StateContracts-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let grader = GradingService(engine: engine)
        let attacks: [(String, String)] = [
            ("l054-e4", "; UPDATE products SET price=0"),
            ("l066-e5", "; UPDATE orders SET total=0; UPDATE order_items SET unit_price=0"),
            ("l081-e4", "; UPDATE debit_requests SET amount=31"),
            ("l085-e4", "; UPDATE orders SET total=0"),
            ("l086-e4", "; UPDATE products SET stock=0")
        ]
        do {
            for (id, change) in attacks {
                let exercise = try #require(course.exercises.first { $0.id == id })
                let grade = try await grader.grade(sql: exercise.solutionSQL + change, exercise: exercise, curriculum: course)
                #expect(!grade.passed, "Unrequested state changes must fail: \(id)")
            }
            let function = try #require(course.exercises.first { $0.id == "l065-e4" })
            let volatile = try await grader.grade(sql: function.solutionSQL.replacingOccurrences(of: "IMMUTABLE", with: "VOLATILE"), exercise: function, curriculum: course)
            #expect(!volatile.passed)
            let sequence = try #require(course.exercises.first { $0.id == "l051-e4" })
            let fake = try await grader.grade(sql: "SELECT 10::bigint AS first_batch,15::bigint AS second_batch,20::bigint AS third_batch", exercise: sequence, curriculum: course)
            #expect(!fake.passed)
            let returning = try #require(course.exercises.first { $0.id == "l034-e4" })
            let omitted = returning.solutionSQL.components(separatedBy: " RETURNING").first! + ";"
            #expect(try await !grader.grade(sql: omitted, exercise: returning, curriculum: course).passed)
            await engine.shutdown(); try? FileManager.default.removeItem(at: base)
        } catch { await engine.shutdown(); try? FileManager.default.removeItem(at: base); throw error }
    }

    @Test func jsonbNumbersCompareExactlyWithoutChangingQuotedValuesOrArrayOrder() {
        func value(_ text: String) -> QueryResult {
            QueryResult(columns: [QueryColumn(name: "state", typeOID: 3802)], rows: [[text]], command: "", duration: 0)
        }
        let expected = value(#"{"a": [30, 1.25], "s": "30.00", "z": 12345678901234567890123456789012345678901234567890.01}"#)
        let same = value(#"{"a": [30.000, 1.2500], "s": "30.00", "z": 12345678901234567890123456789012345678901234567890.0100}"#)
        #expect(ResultComparator.compare(actual: same, expected: expected, ordered: false, columnNames: true) == nil)
        #expect(ResultComparator.compare(actual: value(#"{"a": [1.25, 30], "s": "30.00", "z": 12345678901234567890123456789012345678901234567890.01}"#), expected: expected, ordered: false, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: value(#"{"a": [30, 1.25], "s": "30", "z": 12345678901234567890123456789012345678901234567890.01}"#), expected: expected, ordered: false, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: value(#"{"a": [30, 1.25], "s": "30.00", "z": 12345678901234567890123456789012345678901234567890.02}"#), expected: expected, ordered: false, columnNames: true) != nil)
    }
}
