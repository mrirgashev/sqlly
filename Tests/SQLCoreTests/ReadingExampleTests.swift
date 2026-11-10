import Foundation
import Testing
@testable import SQLCore

@Suite(.serialized)
struct ReadingExampleTests {
    private struct ExamplePack: Decodable {
        let version: String
        let examples: [Example]
    }
    private struct Example: Decodable {
        let lessonID: String
        let fixtureID: String
        let sql: String
        let setupSQL: String?
        let columns: [String]
        let rows: [[String?]]
    }

    @Test func everyPracticalReadingExampleMatchesPostgresAndBothLanguages() async throws {
        let english = try Curriculum.load()
        let russian = try Curriculum.load(language: .russian)
        let url = try #require(SQLLYResources.coreBundle?.url(forResource: "reading-examples", withExtension: "json", subdirectory: "Resources"))
        let pack = try JSONDecoder().decode(ExamplePack.self, from: Data(contentsOf: url))
        #expect(pack.version == english.version)
        #expect(pack.examples.map(\.lessonID) == english.lessons.map(\.id))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-ReadingExamples-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: root)
        do {
            try await engine.start()
            for example in pack.examples {
                do {
                    let fixture = try #require(english.fixtures[example.fixtureID])
                    let result = try await engine.execute(sql: example.sql, fixture: fixture, setup: example.setupSQL)
                    #expect(result.columns.map(\.name) == example.columns, "Column mismatch in \(example.lessonID)")
                    #expect(result.rows == example.rows, "Reading result mismatch in \(example.lessonID)")
                    for course in [english, russian] {
                        let lesson = try #require(course.lessons.first { $0.id == example.lessonID })
                        let body = lesson.sections[4].body
                        #expect(body.contains(example.sql.trimmingCharacters(in: .whitespacesAndNewlines)), "Missing runnable example in \(example.lessonID)")
                        if let setup = example.setupSQL { #expect(body.contains(setup.trimmingCharacters(in: .whitespacesAndNewlines))) }
                    }
                } catch {
                    Issue.record("Reading example \(example.lessonID) failed: \(error.localizedDescription)")
                }
            }
            await engine.shutdown()
            try? FileManager.default.removeItem(at: root)
        } catch {
            await engine.shutdown()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}
