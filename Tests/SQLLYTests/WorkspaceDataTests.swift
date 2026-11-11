import Foundation
import SQLCore
import Testing
@testable import SQLLY

@MainActor @Suite(.serialized)
struct WorkspaceDataTests {
    @Test func upgradeUpdatesOnlyUnsubmittedGeneratedStarters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-EditorUpgrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore(url: root.appendingPathComponent("progress.sqlite"))
        let generated = PracticeTableContext.selectSQL(for: "products")
        let submitted = PracticeTableContext.selectSQL(for: "customers")
        let edited = "SELECT id, status FROM orders;"
        try store.saveDraft(generated, for: "l001-e2")
        try store.saveDraft(submitted, for: "l001-e1")
        try store.saveDraft(edited, for: "l001-e3")
        try store.setPosition("l001-e2")
        let attempt = Attempt(exerciseID: "l001-e1", sql: submitted, passed: true, feedback: "Correct", submissionKind: .gradedCode)
        try store.record(attempt)

        let model = WorkspaceModel(progressStore: store, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        #expect(model.selection == "l001-e2")
        #expect(model.sql == model.defaultEditorSQL)
        #expect(try store.drafts()["l001-e2"] == model.defaultEditorSQL)
        #expect(try store.drafts()["l001-e1"] == submitted)
        #expect(try store.drafts()["l001-e3"] == edited)
        #expect(try store.attempts().map(\.id) == [attempt.id])
        model.sql = generated
        await model.shutdown()

        let reopened = WorkspaceModel(progressStore: store, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("reopened-engine")))
        #expect(reopened.sql == generated)
        await reopened.shutdown()
    }

    @Test func savedStarterAndEmptyDraftsSurviveNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-SavedStarters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore(url: root.appendingPathComponent("progress.sqlite"))
        let model = WorkspaceModel(progressStore: store, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        let exercise = try #require(model.course?.exercises.first {
            !["predict", "choose", "explain"].contains($0.kind) &&
            $0.starterSQL.split(separator: "\n").contains { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
        })
        model.select(exercise.id)
        model.sql = exercise.starterSQL
        model.select("l001.read.0")
        model.select(exercise.id)
        #expect(model.sql == exercise.starterSQL)
        model.sql = ""
        model.select("l001.read.0")
        model.select(exercise.id)
        #expect(model.sql.isEmpty)
        #expect(try store.drafts()[exercise.id] == "")
        await model.shutdown()
    }

    @Test func readingVisitsCompleteImmediatelyAndRetainSavedWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-ReadingVisits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore(url: root.appendingPathComponent("progress.sqlite"))
        let model = WorkspaceModel(progressStore: store, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        let first = try #require(model.course?.steps.first)
        #expect(model.progress[first.id]?.completed == true)
        model.select("l001-e1")
        #expect(model.progress["l001-e1"]?.completed != true)
        let draft = "SELECT name FROM customers WHERE city IS NULL;"
        model.sql = draft
        model.select("l001.read.9")
        #expect(model.progress["l001.read.9"]?.completed == true)
        #expect(try store.allProgress()["l001.read.9"]?.completed == true)
        model.select("l001-e1")
        #expect(model.sql == draft)
        await model.shutdown()

        let restored = WorkspaceModel(progressStore: store, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("restored-engine")))
        #expect(restored.selection == "l001-e1")
        #expect(restored.sql == draft)
        #expect(restored.progress["l001.read.9"]?.completed == true)
        #expect(restored.progress["l001-e1"]?.completed != true)
        await restored.shutdown()
    }

    @Test func blankEditorShowsEveryStartingRowAndUsesTheTaskTable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-StartingData-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = PostgresEngine(baseURL: root.appendingPathComponent("engine"))
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")), practiceEngine: engine)
        // More than the former 50-row preview boundary verifies both result tabs.
        let original = try JSONEncoder().encode(try Curriculum.load())
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var fixtures = try #require(object["fixtures"] as? [String: String])
        fixtures["retail", default: ""] += """
        INSERT INTO customers(id,name,joined_on)
        SELECT n,'Customer ' || n,DATE '2024-01-01' FROM generate_series(101,160) n;
        """
        object["fixtures"] = fixtures
        model.course = try JSONDecoder().decode(Curriculum.self, from: JSONSerialization.data(withJSONObject: object))
        model.liveEnabled = false
        model.select("l001-e1")
        #expect(model.sql == L.text("-- Write your SQL query here", language: model.language))
        #expect(model.selectedResultTab == "Results")
        model.engineReady = true
        await model.refreshPracticeData()
        #expect(model.dataError == nil)
        #expect(model.preview?.rows.count == 66)
        let startingData = try #require(model.preview)
        #expect(model.displayedResult == startingData)
        #expect(!model.isLiveRunning)
        model.sql = "SELECT '-- A string' AS a_draft;"
        await model.run()
        #expect(model.displayedResult?.rows == [["-- A string"]])
        #expect(model.preview == startingData)

        for blank in ["", " \t\r\n", "-- Draft a query\r\n; /* outer /* nested */ comment */ ;"] {
            model.sql = blank
            #expect(model.displayedResult == startingData)
        }
        await model.run(submit: true)
        #expect(model.attempts.isEmpty)
        #expect(model.feedback == "Write a SQL statement before submitting.")
        #expect(model.displayedResult == startingData)
        model.selectedResultTab = "Data"
        await model.run()
        #expect(model.selectedResultTab == "Results")
        #expect(model.displayedResult == startingData)

        model.engineReady = false
        model.select("l001-e2")
        #expect(model.selectedDataTable == "products")
        #expect(model.sql == model.defaultEditorSQL)
        #expect(model.preview == nil)
        #expect(model.displayedResult == nil)
        model.engineReady = true
        await model.refreshPracticeData()
        #expect(model.displayedResult?.rows.count == 8)
        #expect(model.displayedResult?.columns.map(\.name).contains("stock") == true)
        await model.previewTable("customers; DROP TABLE products")
        #expect(model.selectedDataTable == "products")
        #expect(model.preview?.rows.count == 8)

        model.engineReady = false
        model.select("l022-e1")
        model.engineReady = true
        await model.previewTable("customers")
        #expect(model.preview?.rows.count == 66)
        #expect(model.displayedResult?.rows.count == 12)
        #expect(model.displayedResult?.columns.map(\.name).contains("ordered_on") == true)

        model.sql = "SELECT 42;"
        model.reset()
        #expect(model.sql == model.defaultEditorSQL)
        #expect(model.displayedResult?.rows.count == 12)
        await model.shutdown()
    }

    @Test func tasksWithoutStartingTablesOpenWithAnInstructionComment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-NoSource-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")), practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        model.select("l051-e1")
        #expect(model.practiceTables.isEmpty)
        #expect(model.sql == L.text("-- Write your SQL query here", language: model.language))
        #expect(model.selectedDataTable.isEmpty)
        #expect(model.preview == nil)
        #expect(model.displayedResult == nil)
        await model.shutdown()
    }
}
