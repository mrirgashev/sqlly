import Foundation
import Testing
import SQLCore
@testable import SQLLY

@MainActor @Suite(.serialized)
struct SolutionRevealTests {
    @Test func acceptUnlocksOnlyAfterTenDistinctFailuresAndNeverOpensAutomatically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-Accept-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let previousLive = UserDefaults.standard.object(forKey: "liveExecution")
        defer {
            if let previousLive { UserDefaults.standard.set(previousLive, forKey: "liveExecution") }
            else { UserDefaults.standard.removeObject(forKey: "liveExecution") }
        }
        let store = try ProgressStore(url: root.appendingPathComponent("progress.sqlite"))
        let engine = PostgresEngine(baseURL: root.appendingPathComponent("engine"))
        let model = WorkspaceModel(progressStore: store, practiceEngine: engine)
        let exercise = try #require(model.course?.exercises.first)
        model.select(exercise.id)
        model.liveEnabled = false
        model.engineReady = true
        do {
            #expect(SolutionAccessPolicy.requiredDistinctFailures == 10)
            #expect(!model.canRevealSolution)
            model.setSolutionRevealed(true)
            #expect(!model.showSolution)
            let draft = model.sql
            model.loadWorkedSolution()
            #expect(model.sql == draft)

            model.sql = "SELECT 101 AS not_the_required_columns;"
            await model.run()
            #expect(model.solutionAccess.distinctFailedCodeAttempts == 0)
            for index in 0..<9 {
                model.sql = "SELECT \(101 + index) AS not_the_required_columns;"
                await model.run(submit: true)
                #expect(model.feedbackPassed == false)
                #expect(model.solutionAccess.distinctFailedCodeAttempts == index + 1)
                #expect(!model.canRevealSolution)
                model.setSolutionRevealed(true)
                #expect(!model.showSolution)
                if index == 0 {
                    await model.run(submit: true)
                    model.sql = "-- same code with different formatting\nselect 101 as NOT_THE_REQUIRED_COLUMNS ;"
                    await model.run(submit: true)
                    #expect(model.solutionAccess.distinctFailedCodeAttempts == 1)
                }
            }
            // Passing an exercise is not an early-reveal shortcut.
            model.sql = exercise.solutionSQL
            await model.run(submit: true)
            #expect(model.feedbackPassed == true)
            #expect(!model.canRevealSolution)
            model.setSolutionRevealed(true)
            #expect(!model.showSolution)

            // A genuine learner SQL error is also an unsuccessful submission.
            model.sql = "SELEC 110 AS not_the_required_columns;"
            await model.run(submit: true)
            #expect(model.queryError != nil)
            #expect(model.attempts.first?.submissionKind == .gradedCode)
            #expect(model.solutionAccess.distinctFailedCodeAttempts == 10)
            #expect(model.canRevealSolution)
            #expect(!model.showSolution)
            model.setSolutionRevealed(true)
            #expect(model.showSolution)
            model.loadWorkedSolution()
            #expect(model.sql == exercise.solutionSQL)

            let other = try #require(model.course?.exercises.dropFirst().first)
            model.select(other.id)
            #expect(!model.canRevealSolution && !model.showSolution)
            model.select(exercise.id)
            #expect(model.canRevealSolution && !model.showSolution)
            await model.shutdown()

            let reopenedStore = try ProgressStore(url: root.appendingPathComponent("progress.sqlite"))
            let reopened = WorkspaceModel(progressStore: reopenedStore, practiceEngine: PostgresEngine(baseURL: root.appendingPathComponent("unused-engine")))
            #expect(reopened.selection == exercise.id)
            #expect(reopened.solutionAccess.distinctFailedCodeAttempts == 10)
            #expect(reopened.canRevealSolution && !reopened.showSolution)
            await reopened.shutdown()
        } catch {
            await model.shutdown()
            throw error
        }
    }

    @Test func engineFailureDoesNotUnlockOrCountAsAnIncorrectSolution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-Accept-Offline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = PostgresEngine(baseURL: root.appendingPathComponent("engine"))
        await engine.shutdown()
        let model = WorkspaceModel(progressStore: try ProgressStore(url: root.appendingPathComponent("progress.sqlite")), practiceEngine: engine)
        let exercise = try #require(model.course?.exercises.first)
        model.select(exercise.id)
        model.engineReady = true
        model.sql = "SELECT 42 AS answer;"
        await model.run(submit: true)
        #expect(model.attempts.first?.submissionKind == .infrastructureFailure)
        #expect(model.solutionAccess.distinctFailedCodeAttempts == 0)
        #expect(!model.canRevealSolution && !model.showSolution)
        await model.shutdown()
    }
}
