import Foundation
import Testing
@testable import SQLCore

@Suite(.serialized)
struct GradingFailureTests {
    private var course: Curriculum {
        Curriculum(title: "Failure attribution", version: "1", postgresVersion: PostgresEngine.version,
                   fixtures: ["a": "CREATE TABLE counter(n integer); INSERT INTO counter VALUES(1);",
                              "b": "CREATE TABLE counter(n integer); INSERT INTO counter VALUES(10);"], modules: [])
    }
    private func exercise(solution: String = "SELECT n FROM counter", validation: String? = nil) -> Exercise {
        Exercise(id: "failure-attribution", title: "Read the counter", prompt: "", difficulty: "Beginner", kind: validation == nil ? "query" : "modify",
                 starterSQL: "", solutionSQL: solution, fixtureIDs: ["a", "b"], ordered: true, columnNames: true,
                 hints: ["Inspect counter"], explanation: "", validationSQL: validation)
    }
    private func withEngine(runtimeURL: URL? = nil, _ body: (PostgresEngine) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-GradingFailures-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base, runtimeURL: runtimeURL)
        do { try await body(engine); await engine.shutdown(); try? FileManager.default.removeItem(at: base) }
        catch { await engine.shutdown(); try? FileManager.default.removeItem(at: base); throw error }
    }
    private func expectSubmission(_ sql: String, grader: GradingService, exercise: Exercise,
                                  state: String, origin: PostgresError.Origin = .submittedStatement) async throws {
        do {
            _ = try await grader.grade(sql: sql, exercise: exercise, curriculum: course)
            Issue.record("Expected a learner submission error for \(sql)")
        } catch let failure as GradingSubmissionError {
            #expect(failure.sqlState == state)
            #expect(failure.underlying.origin == origin)
            #expect(!failure.message.isEmpty)
            #expect(failure.message == failure.underlying.message)
            #expect(failure.localizedDescription == failure.underlying.localizedDescription)
        }
    }

    @Test func syntaxPermissionAndTimeoutFailuresAreTypedSubmissions() async throws {
        try await withEngine { engine in
            let grader = GradingService(engine: engine)
            try await expectSubmission("SELEC n FROM counter", grader: grader, exercise: exercise(), state: "42601")
            try await expectSubmission("SELECT rolpassword FROM pg_authid", grader: grader, exercise: exercise(), state: "42501")
            try await expectSubmission("SELECT pg_sleep(10)", grader: grader, exercise: exercise(), state: "57014")
        }
    }

    @Test func correctAlternativeAndIncorrectResultsKeepTheirExistingGrades() async throws {
        try await withEngine { engine in
            let grader = GradingService(engine: engine)
            let correct = try await grader.grade(sql: "SELECT c.n::bigint AS n FROM counter AS c", exercise: exercise(), curriculum: course)
            #expect(correct.passed && correct.fixturesPassed == 2 && correct.fixturesTotal == 2)
            #expect(correct.result?.rows == [["1"]])
            let wrong = try await grader.grade(sql: "SELECT n+1 AS n FROM counter", exercise: exercise(), curriculum: course)
            #expect(!wrong.passed && wrong.fixturesPassed == 0 && wrong.fixturesTotal == 2)
            #expect(wrong.result?.rows == [["2"]])
        }
    }

    @Test func invalidFixturesAndSetupAreSystemErrors() async throws {
        try await withEngine { engine in
            let invalid = Curriculum(title: "Invalid fixture", version: "1", postgresVersion: PostgresEngine.version,
                                     fixtures: ["a": "CREATE TABL counter(n integer);", "b": ""], modules: [])
            do {
                _ = try await GradingService(engine: engine).grade(sql: "SELECT 1", exercise: exercise(), curriculum: invalid)
                Issue.record("Invalid fixture unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState == "42601" && error.origin == .system)
            }
            do {
                _ = try await engine.execute(sql: "SELECT 1", fixture: "", setup: "SELEC 1")
                Issue.record("Invalid setup unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState == "42601" && error.origin == .system)
            }
        }
    }

    @Test func invalidQueryReferenceIsNotAttributedToLearner() async throws {
        try await withEngine { engine in
            do {
                _ = try await GradingService(engine: engine).grade(sql: "SELECT n FROM counter", exercise: exercise(solution: "SELEC n FROM counter"), curriculum: course)
                Issue.record("Invalid reference unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState == "42601" && error.origin == .submittedStatement)
            }
        }
    }

    @Test func destructiveCandidateCanBreakAValidatedStateContract() async throws {
        try await withEngine { engine in
            let task = exercise(solution: "UPDATE counter SET n=n+1", validation: "SELECT n FROM counter")
            let grader = GradingService(engine: engine)
            let good = try await grader.grade(sql: "UPDATE counter SET n=1+n", exercise: task, curriculum: course)
            #expect(good.passed && good.fixturesPassed == 2)
            try await expectSubmission("DROP TABLE counter", grader: grader, exercise: task, state: "42P01", origin: .validation)
        }
    }

    @Test func brokenStateReferencesAndChecksAreRejectedBeforeCandidate() async throws {
        try await withEngine { engine in
            let grader = GradingService(engine: engine)
            do {
                let invalidReference = exercise(solution: "SELEC n FROM counter", validation: "SELECT n FROM counter")
                _ = try await grader.grade(sql: "DROP TABLE counter", exercise: invalidReference, curriculum: course)
                Issue.record("Invalid state reference unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState == "42601" && error.origin == .submittedStatement)
            }
            do {
                let invalidCheck = exercise(solution: "UPDATE counter SET n=n+1", validation: "SELECT missing_column FROM counter")
                _ = try await grader.grade(sql: "SELEC n FROM counter", exercise: invalidCheck, curriculum: course)
                Issue.record("Invalid trusted check unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState == "42703" && error.origin == .validation)
            }
        }
    }

    @Test func missingRuntimeAndTerminalEngineRemainInfrastructureFailures() async throws {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-NoRuntime-\(UUID().uuidString)")
        try await withEngine(runtimeURL: absent) { engine in
            do {
                _ = try await GradingService(engine: engine).grade(sql: "SELEC 1", exercise: exercise(), curriculum: course)
                Issue.record("Missing runtime unexpectedly succeeded")
            } catch let error as PostgresError {
                #expect(error.sqlState.isEmpty && error.origin == .system)
                #expect(error.message.contains("runtime is missing"))
            }
        }
        try await withEngine { engine in
            await engine.shutdown()
            do {
                _ = try await GradingService(engine: engine).grade(sql: "SELEC 1", exercise: exercise(), curriculum: course)
                Issue.record("Terminal engine unexpectedly accepted grading")
            } catch let error as PostgresError {
                #expect(error.sqlState.isEmpty && error.origin == .system)
                #expect(error.message.contains("shutting down"))
            }
        }
    }

    @Test func systemSQLStateClassesNeverBecomeSubmissionFailures() {
        let infrastructure = ["08000", "08006", "53000", "53100", "53200", "53300", "58000", "58030", "XX000", "XX001", "57P01", "57P02", "57P03", "57P04", ""]
        for origin in [PostgresError.Origin.submittedStatement, .validation] {
            for state in infrastructure {
                #expect(!GradingService.isSubmissionFailure(PostgresError("Infrastructure", sqlState: state, origin: origin)), "Excluded SQLSTATE: \(state)")
            }
            for state in ["42601", "42P01", "42501", "22012", "23505", "40001", "40P01", "55P03", "57014"] {
                #expect(GradingService.isSubmissionFailure(PostgresError("Submitted SQL", sqlState: state, origin: origin)), "Submission SQLSTATE: \(state)")
            }
        }
        #expect(PostgresError("Default origin", sqlState: "42601").origin == .system)
        #expect(!GradingService.isSubmissionFailure(PostgresError("Fixture syntax", sqlState: "42601")))
    }
}
