import Foundation
import SQLCore
import Testing
@testable import SQLLY

@MainActor @Suite(.serialized)
struct WorkspaceDataTests {
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

    @Test func dataLoadsEveryStartingRowAndTaskChangesUseTheCorrectTable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-StartingData-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = PostgresEngine(baseURL: root.appendingPathComponent("engine"))
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")), practiceEngine: engine)
        // More than the former 50-row preview boundary verifies the normal Data path.
        let original = try JSONEncoder().encode(try Curriculum.load())
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var fixtures = try #require(object["fixtures"] as? [String: String])
        fixtures["retail", default: ""] += """
        INSERT INTO customers(id,name,joined_on)
        SELECT n,'Customer ' || n,DATE '2024-01-01' FROM generate_series(101,160) n;
        """
        object["fixtures"] = fixtures
        model.course = try JSONDecoder().decode(Curriculum.self, from: JSONSerialization.data(withJSONObject: object))
        model.select("l001-e1")
        #expect(model.sql == PracticeTableContext.selectSQL(for: "customers"))
        #expect(model.selectedResultTab == "Results")
        model.engineReady = true
        await model.refreshPracticeData()
        #expect(model.dataError == nil)
        #expect(model.preview?.rows.count == 66)
        #expect(model.selectedResultTab == "Results")
        let startingRows = model.preview?.rows
        model.sql = "SELECT 1 AS a_draft;"
        #expect(model.preview?.rows == startingRows)
        model.engineReady = false
        model.select("l001-e2")
        #expect(model.selectedDataTable == "products")
        #expect(model.sql == PracticeTableContext.selectSQL(for: "products"))
        #expect(model.preview == nil)
        model.engineReady = true
        await model.refreshPracticeData()
        #expect(model.preview?.rows.count == 8)
        #expect(model.preview?.columns.map(\.name).contains("stock") == true)
        await model.previewTable("customers; DROP TABLE products")
        #expect(model.selectedDataTable == "products")
        #expect(model.preview?.rows.count == 8)
        await model.shutdown()
    }

    @Test func tasksWithoutStartingTablesHaveExecutableDefaults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-NoSource-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")), practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("engine")))
        model.select("l051-e1")
        #expect(model.practiceTables.isEmpty)
        #expect(model.sql == "SELECT 1;")
        #expect(model.selectedDataTable.isEmpty)
        #expect(model.preview == nil)
        await model.shutdown()
    }
}
