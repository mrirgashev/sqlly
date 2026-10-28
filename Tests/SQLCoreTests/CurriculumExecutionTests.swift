import Foundation
import Testing
@testable import SQLCore

/// Executes authored answers against the packaged engine, rather than only
/// checking that curriculum JSON parses. This is deliberately an integration
/// test: schema changes, constraints, PL/pgSQL and all fixtures are real SQL.
@Suite(.serialized)
struct CurriculumExecutionTests {
    private func report(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }
    private struct LessonPreview: Codable {
        let columns: [String]
        let rows: [[String?]]
        let rowCount: Int
    }

    @Test func curriculumChecksRequireConstraintsAndRealChanges() async throws {
        let course = try Curriculum.load()
        let notes = try #require(course.exercises.first { $0.id == "l049-e1" })
        let reservations = try #require(course.exercises.first { $0.id == "l050-e1" })
        let product = try #require(course.exercises.first { $0.id == "l034-e1" })
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftNegative-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let grader = GradingService(engine: engine)
        do {
            let missingForeignKey = try await grader.grade(sql: "CREATE TABLE customer_notes(id integer PRIMARY KEY,customer_id integer NOT NULL,body text NOT NULL); INSERT INTO customer_notes VALUES(1,1,'Call after 5');", exercise: notes, curriculum: course)
            #expect(!missingForeignKey.passed, "Matching visible rows cannot replace a required foreign key")
            let missingCheck = try await grader.grade(sql: "CREATE TABLE reservations(id integer PRIMARY KEY,quantity integer NOT NULL DEFAULT 1); INSERT INTO reservations(id) VALUES(1);", exercise: reservations, curriculum: course)
            #expect(!missingCheck.passed, "Matching default values cannot replace the required quantity CHECK")
            let fakeInsert = try await grader.grade(sql: "SELECT 50 AS id,'Ruler'::text AS name,3.50::numeric AS price,15 AS stock", exercise: product, curriculum: course)
            #expect(!fakeInsert.passed, "Returning an invented product row cannot replace INSERT")
            let namedConstraints = try await grader.grade(sql: "CREATE TABLE customer_notes(id integer CONSTRAINT my_primary_key PRIMARY KEY,customer_id integer NOT NULL CONSTRAINT my_customer_link REFERENCES customers(id),body text NOT NULL); INSERT INTO customer_notes VALUES(1,1,'Call after 5');", exercise: notes, curriculum: course)
            #expect(namedConstraints.passed, "Equivalent constraints with different names should be accepted")
            await engine.stop(); try? FileManager.default.removeItem(at: base)
        } catch {
            await engine.stop(); try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func lessonExpectedResultsMatchPostgres() async throws {
        let course = try Curriculum.load()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftPreviews-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        var previews: [String: LessonPreview] = [:]
        do {
            for lesson in course.lessons {
                guard let exercise = lesson.exercises.first else { Issue.record("Lesson has no exercise: \(lesson.id)"); continue }
                do {
                    let fixture = course.fixture(for: exercise)
                    let result: QueryResult
                    if let validation = exercise.stateValidationSQL ?? exercise.validationSQL, !validation.isEmpty {
                        result = try await engine.validate(sql: exercise.solutionSQL, fixture: fixture, verificationSQL: validation)
                    } else { result = try await engine.execute(sql: exercise.solutionSQL, fixture: fixture) }
                    previews[lesson.id] = LessonPreview(columns: result.columns.map(\.name), rows: Array(result.rows.prefix(8)), rowCount: result.rows.count)
                } catch { Issue.record("Lesson preview failed for \(lesson.id): \(error.localizedDescription)") }
            }
            #expect(previews.count == course.lessons.count)
            if let output = ProcessInfo.processInfo.environment["QUERYCRAFT_LESSON_PREVIEWS_PATH"] {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(previews).write(to: URL(fileURLWithPath: output), options: .atomic)
            }
            report("Expected-result previews generated for \(previews.count) lessons using PostgreSQL \(PostgresEngine.version).")
            await engine.stop(); try? FileManager.default.removeItem(at: base)
        } catch {
            await engine.stop(); try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func everyReferenceSolutionGradesAcrossEveryFixture() async throws {
        let course = try Curriculum.load()
        #expect(course.exercises.count >= 300)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftCurriculum-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let grader = GradingService(engine: engine)
        var checked = 0
        var sqlAnswers = 0
        var predictions = 0
        var conceptualAnswers = 0
        var fixtureChecks = 0
        var previews: [String: QueryResult] = [:]
        do {
            for exercise in course.exercises {
                #expect(exercise.fixtureIDs.count >= 2, "Exercise must include a second anti-hardcoding fixture: \(exercise.id)")
                do {
                    switch exercise.kind {
                    case "choose":
                        let choices = try #require(exercise.choices, "Missing choices: \(exercise.id)")
                        let correct = try #require(exercise.correctChoiceIDs, "Missing correct choices: \(exercise.id)")
                        #expect(choices.count >= 2)
                        #expect(Set(choices.map(\.id)).count == choices.count)
                        #expect(!correct.isEmpty && Set(correct).isSubset(of: Set(choices.map(\.id))))
                        conceptualAnswers += 1
                    case "explain":
                        let model = try #require(exercise.modelAnswer, "Missing self-assessment rubric: \(exercise.id)")
                        #expect(model.count > 80)
                        #expect(exercise.hints.count >= 2)
                        conceptualAnswers += 1
                    case "predict":
                        for index in exercise.fixtureIDs.indices {
                            let reference = try await engine.execute(sql: exercise.solutionSQL, fixture: course.fixture(for: exercise, index: index))
                            #expect(!reference.columns.isEmpty)
                            if index == 0 { previews[exercise.id] = reference }
                        }
                        predictions += 1
                    default:
                        let grade = try await grader.grade(sql: exercise.solutionSQL, exercise: exercise, curriculum: course)
                        #expect(grade.passed, "Reference failed for \(exercise.id): \(grade.message)")
                        #expect(grade.fixturesPassed == exercise.fixtureIDs.count)
                        if let preview = grade.result { previews[exercise.id] = preview }
                        fixtureChecks += grade.fixturesPassed
                        sqlAnswers += 1
                    }
                } catch {
                    Issue.record("Reference error for \(exercise.id): \(error.localizedDescription)")
                }
                checked += 1
                if checked % 25 == 0 { report("Curriculum verified: \(checked)/\(course.exercises.count) answers, \(fixtureChecks) fixture comparisons") }
            }
            if let output = ProcessInfo.processInfo.environment["QUERYCRAFT_EXPECTED_RESULTS_PATH"] {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(previews).write(to: URL(fileURLWithPath: output), options: .atomic)
            }
            report("Curriculum reference validation complete: \(checked) answers; \(sqlAnswers) SQL answers; \(predictions) predictions; \(conceptualAnswers) conceptual responses; \(fixtureChecks) fixture comparisons; \(previews.count) previews.")
            await engine.stop(); try? FileManager.default.removeItem(at: base)
        } catch {
            await engine.stop(); try? FileManager.default.removeItem(at: base)
            throw error
        }
    }
}
