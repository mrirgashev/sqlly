import Foundation
import Testing
@testable import SQLCore

struct PracticeTableContextTests {
    @Test func everyPublishedExerciseHasAnExplicitContextInBothLanguages() throws {
        for language in [CourseLanguage.english, .russian] {
            let course = try Curriculum.load(language: language)
            #expect(PracticeTableContext.exerciseIDs == Set(course.exercises.map(\.id)))
            for exercise in course.exercises {
                let context = PracticeTableContext.forExercise(exercise)
                #expect(context.tables.count == Set(context.tables).count, "\(exercise.id)")
                #expect(context.primaryTable == context.tables.first)
                for fixtureID in exercise.fixtureIDs {
                    let fixture = try #require(course.fixtures[fixtureID])
                    for table in context.tables {
                        #expect(fixture.contains("CREATE TABLE \(table)("), "\(exercise.id): \(table) must exist before the learner's SQL runs")
                    }
                }
                if let table = context.primaryTable {
                    #expect(context.defaultSQL == "SELECT * FROM public.\"\(table)\";")
                } else {
                    #expect(context.defaultSQL == nil)
                }
            }
        }
    }

    @Test func sourceTablesFollowEachTaskAndTheMainReportingEntity() {
        #expect(PracticeTableContext.forExerciseID("l001-e1").tables == ["customers"])
        #expect(PracticeTableContext.forExerciseID("l001-e2").tables == ["products"])
        #expect(PracticeTableContext.forExerciseID("l001-e3").tables == ["orders"])
        #expect(PracticeTableContext.forExerciseID("l024-e1").tables == ["customers", "orders"])
        #expect(PracticeTableContext.forExerciseID("l029-e3").tables == ["customers", "orders"])
        #expect(PracticeTableContext.forExerciseID("l098-e2").tables == ["products", "order_items", "orders"])
        #expect(PracticeTableContext.forExerciseID("l102-e3").tables == ["orders", "order_items"])
    }

    @Test func expressionCatalogAndNewTableTasksDoNotInventExistingTables() {
        for id in ["l003-e1", "l053-e2", "l051-e1", "l092-e1", "unpublished-task"] {
            let context = PracticeTableContext.forExerciseID(id)
            #expect(context.tables.isEmpty)
            #expect(context.defaultSQL == nil)
        }
        // Designing a new table from existing rows still exposes its real input.
        #expect(PracticeTableContext.forExerciseID("l092-e2").tables == ["products"])
        #expect(PracticeTableContext.forExerciseID("l100-e1").tables == ["accounts"])
    }

    @Test func completeTableQueryQuotesIdentifiersWithoutAddingALimit() {
        #expect(PracticeTableContext.selectSQL(for: "order_items") == "SELECT * FROM public.\"order_items\";")
        #expect(PracticeTableContext.selectSQL(for: "a\"; DROP TABLE products; --") == "SELECT * FROM public.\"a\"\"; DROP TABLE products; --\";")
    }
}
