import Foundation
import Testing
@testable import SQLCore

struct ResultComparisonTests {
    private func result(_ rows: [[String?]], names: [String] = ["value"], types: [UInt32] = [1700]) -> QueryResult {
        QueryResult(columns: zip(names, types).map { QueryColumn(name: $0.0, typeOID: $0.1) }, rows: rows, command: "SELECT", duration: 0)
    }

    @Test func rowOrderPolicyAndDuplicateMultiplicity() {
        let expected = result([["1"], ["2"], ["2"]])
        #expect(ResultComparator.compare(actual: result([["2"], ["1"], ["2"]]), expected: expected, ordered: false, columnNames: true) == nil)
        #expect(ResultComparator.compare(actual: result([["2"], ["1"], ["2"]]), expected: expected, ordered: true, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: result([["1"], ["1"], ["2"]]), expected: expected, ordered: false, columnNames: true) != nil)
    }

    @Test func nullEmptyStringAndLiteralNullAreDistinct() {
        let expected = result([[nil], [""], ["NULL"]], types: [25])
        #expect(ResultComparator.compare(actual: result([["NULL"], [nil], [""]], types: [25]), expected: expected, ordered: false, columnNames: true) == nil)
        #expect(ResultComparator.compare(actual: result([["NULL"], [""], ["NULL"]], types: [25]), expected: expected, ordered: false, columnNames: true) != nil)
    }

    @Test func exactArbitraryNumericPrecision() {
        #expect(ResultComparator.compare(actual: result([["0012.5000"], ["-0.0"], ["1.2e3"]]), expected: result([["12.5"], ["0"], ["1200"]]), ordered: true, columnNames: true) == nil)
        let large = "123456789012345678901234567890123456789012345678901234567890"
        #expect(ResultComparator.compare(actual: result([[large + ".01"]]), expected: result([[large + ".02"]]), ordered: false, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: result([[large + ".0100"]]), expected: result([[large + ".01"]]), ordered: false, columnNames: true) == nil)
    }

    @Test func columnsAndUnambiguousCellBoundaries() {
        let expected = result([["ab", "c"]], names: ["a", "b"], types: [25, 25])
        #expect(ResultComparator.compare(actual: result([["a", "bc"]], names: ["a", "b"], types: [25, 25]), expected: expected, ordered: false, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: result([["ab", "c"]], names: ["x", "y"], types: [25, 25]), expected: expected, ordered: false, columnNames: false) == nil)
        #expect(ResultComparator.compare(actual: result([["ab", "c"]], names: ["x", "y"], types: [25, 25]), expected: expected, ordered: false, columnNames: true) != nil)
        #expect(ResultComparator.compare(actual: result([]), expected: expected, ordered: false, columnNames: false) != nil)
    }
}

struct PersistenceTests {
    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftStorage-\(UUID().uuidString)").appendingPathComponent("progress.sqlite") }

    @Test func survivesConnectionCloseAndReopen() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var state = StepProgress(); state.completed = true; state.bookmarked = true; state.review = true; state.visits = 3
        let sql = "SELECT 'Café, 雪; O''Reilly' AS value;\n-- multiline"
        do {
            let store = try ProgressStore(url: url)
            try store.save(state, for: "lesson.';--")
            try store.saveDraft(sql, for: "lesson.';--")
            try store.record(Attempt(exerciseID: "lesson.';--", sql: sql, passed: false, feedback: "Try again"))
            try store.setPosition("lesson.';--")
        }
        let reopened = try ProgressStore(url: url)
        #expect(try reopened.allProgress()["lesson.';--"]?.completed == true)
        #expect(try reopened.allProgress()["lesson.';--"]?.visits == 3)
        #expect(try reopened.drafts()["lesson.';--"] == sql)
        #expect(try reopened.attempts().first?.sql == sql)
        #expect(try reopened.position() == "lesson.';--")
    }

    @Test func backupMergePreservesLocalDraftAndCompletion() throws {
        let localURL = temporaryURL(), otherURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()); try? FileManager.default.removeItem(at: otherURL.deletingLastPathComponent()) }
        let local = try ProgressStore(url: localURL), other = try ProgressStore(url: otherURL)
        var localState = StepProgress(); localState.completed = true; localState.visits = 4
        var remote = StepProgress(); remote.bookmarked = true; remote.review = true; remote.visits = 2
        try local.save(localState, for: "x"); try local.saveDraft("local", for: "x"); try local.setPosition("local-position")
        try other.save(remote, for: "x"); try other.saveDraft("remote", for: "x"); try other.saveDraft("new", for: "y"); try other.setPosition("remote-position")
        try other.record(Attempt(exerciseID: "x", sql: "SELECT 1", passed: true, feedback: "Correct"))
        let data = try other.exportData()
        try local.importData(data); try local.importData(data)
        let merged = try local.allProgress()["x"]
        #expect(merged?.completed == true); #expect(merged?.review == true); #expect(merged?.bookmarked == true); #expect(merged?.visits == 4)
        #expect(try local.drafts()["x"] == "local"); #expect(try local.drafts()["y"] == "new")
        #expect(try local.position() == "local-position"); #expect(try local.attempts().count == 1)
    }

    @Test func malformedAndFutureBackupsDoNotChangeLocalState() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try ProgressStore(url: url); try store.saveDraft("saved", for: "x")
        #expect(throws: (any Error).self) { try store.importData(Data("invalid".utf8)) }
        var object = try JSONSerialization.jsonObject(with: store.exportData()) as! [String: Any]
        object["formatVersion"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try store.importData(future) }
        #expect(try store.drafts()["x"] == "saved")
    }

    @Test func conflictingBackupAttemptDoesNotOverwriteLocalHistory() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try ProgressStore(url: url)
        let local = Attempt(exerciseID: "x", sql: "SELECT 1", passed: true, feedback: "Local")
        try store.record(local)
        var incoming = local; incoming.sql = "SELECT 2"; incoming.feedback = "Conflicting backup"
        let backup = ProgressBackup(formatVersion: 1, exportedAt: Date(), progress: [:], attempts: [incoming], drafts: [:], position: nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.importData(encoder.encode(backup))
        #expect(try store.attempts().first?.feedback == "Local")
        #expect(try store.attempts().first?.sql == "SELECT 1")
    }

    @Test func damagedDatabaseIsPreservedForRecovery() throws {
        let url = temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a SQLite database".utf8).write(to: url)
        let recovered = try ProgressStore(url: url)
        #expect(recovered.recoveryNotice != nil)
        let preserved = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(preserved.contains { $0.contains("damaged-") })
        #expect(try recovered.allProgress().isEmpty)
    }
}

struct CourseContentTests {
    @Test func completeContentIntegrity() throws {
        let course = try Curriculum.load()
        try course.validate()
        #expect(course.modules.count >= 30)
        #expect(course.exercises.count >= 300)
        #expect(course.lessons.allSatisfy { (5...7).contains($0.exercises.count) })
        #expect(course.lessons.allSatisfy { $0.sections.count >= 11 })
        #expect(course.exercises.allSatisfy { $0.fixtureIDs.count >= 2 })
    }
}

@Suite(.serialized)
struct GradingIntegrationTests {
    @Test func alternativeQueriesPassAndHardcodedAnswersFail() async throws {
        let course = try Curriculum.load()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftGrade-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let exercise = Exercise(id: "test", title: "Price", prompt: "Return prices", difficulty: "beginner", kind: "query", starterSQL: "", solutionSQL: "SELECT amount FROM items", fixtureIDs: ["a", "b"], ordered: false, columnNames: true, hints: ["Select amount"], explanation: "Projection", validationSQL: nil)
        let testCourse = Curriculum(title: course.title, version: course.version, postgresVersion: course.postgresVersion, fixtures: ["a": "CREATE TABLE items(amount numeric); INSERT INTO items VALUES (1),(NULL),(1);", "b": "CREATE TABLE items(amount numeric); INSERT INTO items VALUES (2),(3),(NULL);"], modules: [])
        do {
            let grader = GradingService(engine: engine)
            let alternative = try await grader.grade(sql: "SELECT i.amount FROM items AS i ORDER BY amount DESC NULLS FIRST", exercise: exercise, curriculum: testCourse)
            #expect(alternative.passed); #expect(alternative.fixturesPassed == 2)
            let hardcoded = try await grader.grade(sql: "SELECT 1::numeric AS amount UNION ALL SELECT NULL::numeric UNION ALL SELECT 1::numeric", exercise: exercise, curriculum: testCourse)
            #expect(!hardcoded.passed); #expect(hardcoded.fixturesPassed == 1)
            await engine.stop()
        } catch { await engine.stop(); throw error }
        try? FileManager.default.removeItem(at: base)
    }

    @Test func predictionChecksNullsAndRankTiesAgainstPostgres() async throws {
        let course = try Curriculum.load()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftPrediction-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        do {
            let service = GradingService(engine: engine)
            let predictions = course.exercises.filter { $0.kind == "predict" }
            #expect(predictions.count == 2)
            for exercise in predictions {
                let expected = try await engine.execute(sql: exercise.solutionSQL, fixture: course.fixture(for: exercise))
                let encoded = String(decoding: try JSONEncoder().encode(expected.rows), as: UTF8.self)
                let correct = try await service.gradeResponse(encoded, exercise: exercise, curriculum: course)
                #expect(correct.passed)
                let wrong = try await service.gradeResponse("[[\"incorrect\"]]", exercise: exercise, curriculum: course)
                #expect(!wrong.passed)
                #expect(wrong.result == nil)
            }
            await engine.stop()
        } catch { await engine.stop(); throw error }
        try? FileManager.default.removeItem(at: base)
    }

    @Test func choicesRequireExactlyAllValidOptions() async throws {
        let course = try Curriculum.load()
        let engine = PostgresEngine()
        let service = GradingService(engine: engine)
        let exercise = try #require(course.exercises.first { $0.kind == "choose" && ($0.correctChoiceIDs?.count ?? 0) > 1 })
        let answer = try #require(exercise.correctChoiceIDs)
        let encoded = String(decoding: try JSONEncoder().encode(answer.reversed().map { $0 }), as: UTF8.self)
        #expect(try await service.gradeResponse(encoded, exercise: exercise, curriculum: course).passed)
        #expect(try await !service.gradeResponse("[]", exercise: exercise, curriculum: course).passed)
        let tooMany = String(decoding: try JSONEncoder().encode((exercise.choices ?? []).map(\.id)), as: UTF8.self)
        #expect(try await !service.gradeResponse(tooMany, exercise: exercise, curriculum: course).passed)
        let explanation = try #require(course.exercises.first { $0.kind == "explain" })
        await #expect(throws: (any Error).self) { try await service.gradeResponse("A plausible sentence", exercise: explanation, curriculum: course) }
    }
}
