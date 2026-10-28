import Foundation
import Testing
@testable import SQLCore

private actor LiveProbe {
    var executions: [String] = []
    var results: [String] = []
    var failures: [String] = []
    private var slowGate: CheckedContinuation<Void, Never>?
    func execute(_ sql: String, _ fixture: String) async throws -> QueryResult {
        executions.append(sql)
        if sql == "slow" { await withCheckedContinuation { slowGate = $0 } }
        if sql == "invalid" { throw PostgresError("syntax error", sqlState: "42601") }
        return QueryResult(columns: [QueryColumn(name: "value", typeOID: 25)], rows: [[sql]], command: "SELECT", duration: 0)
    }
    func observe(_ event: LiveQueryEvent) {
        switch event {
        case let .result(_, result): results.append(result.rows.first?.first.flatMap { $0 } ?? "")
        case let .failure(context, _): failures.append(context)
        default: break
        }
    }
    func releaseSlow() { slowGate?.resume(); slowGate = nil }
    func waitForExecution(_ sql: String) async throws {
        for _ in 0..<1000 {
            if executions.contains(sql) { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw ContentError.invalid("Live test executor did not start.")
    }
}

struct LiveExecutionTests {
    @Test func rapidTypingRunsOnlyFinalDraft() async throws {
        let probe = LiveProbe()
        let controller = LiveQueryController(delay: .milliseconds(40)) { try await probe.execute($0, $1) }
        for index in 0..<30 {
            await controller.submit(sql: "draft-\(index)", fixture: "", context: "exercise", revision: UInt64(index + 1)) { await probe.observe($0) }
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await probe.executions == ["draft-29"])
        #expect(await probe.results == ["draft-29"])
    }

    @Test func runningDraftIsSupersededAndQueuedEditsAreCoalesced() async throws {
        let probe = LiveProbe()
        let controller = LiveQueryController(delay: .milliseconds(10)) { try await probe.execute($0, $1) }
        await controller.submit(sql: "slow", fixture: "", context: "old") { await probe.observe($0) }
        try await probe.waitForExecution("slow")
        await controller.submit(sql: "middle", fixture: "", context: "new") { await probe.observe($0) }
        try await Task.sleep(for: .milliseconds(25))
        await controller.submit(sql: "latest", fixture: "", context: "new") { await probe.observe($0) }
        try await Task.sleep(for: .milliseconds(80))
        await probe.releaseSlow()
        try await probe.waitForExecution("latest")
        try await Task.sleep(for: .milliseconds(30))
        #expect(await probe.executions == ["slow", "latest"])
        #expect(await probe.results == ["latest"])
    }

    @Test func cancellationAndReorderedClientRequestsNeverPublishStaleResults() async throws {
        let probe = LiveProbe()
        let controller = LiveQueryController(delay: .milliseconds(40)) { try await probe.execute($0, $1) }
        await controller.submit(sql: "cancelled", fixture: "", context: "old", revision: 1) { await probe.observe($0) }
        await controller.cancel(revision: 2)
        try await Task.sleep(for: .milliseconds(90))
        #expect(await probe.executions.isEmpty)
        await controller.submit(sql: "new", fixture: "", context: "new", revision: 4) { await probe.observe($0) }
        await controller.submit(sql: "out-of-order", fixture: "", context: "old", revision: 3) { await probe.observe($0) }
        await controller.cancel(revision: 2)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await probe.executions == ["new"])
        #expect(await probe.results == ["new"])
    }

    @Test func errorDoesNotBlockNextLiveQuery() async throws {
        let probe = LiveProbe()
        let controller = LiveQueryController(delay: .milliseconds(10)) { try await probe.execute($0, $1) }
        await controller.submit(sql: "invalid", fixture: "", context: "invalid") { await probe.observe($0) }
        try await Task.sleep(for: .milliseconds(60))
        await controller.submit(sql: "fixed", fixture: "", context: "fixed") { await probe.observe($0) }
        try await Task.sleep(for: .milliseconds(60))
        #expect(await probe.failures == ["invalid"])
        #expect(await probe.results == ["fixed"])
    }
}

struct LocalizationAndFlowTests {
    @Test func russianContentPreservesEveryExecutableContract() throws {
        let english = try Curriculum.load()
        let russian = try Curriculum.load(language: .russian)
        #expect(english.fixtures == russian.fixtures)
        #expect(english.lessons.map(\.id) == russian.lessons.map(\.id))
        #expect(english.exercises.map(\.id) == russian.exercises.map(\.id))
        for (en, ru) in zip(english.exercises, russian.exercises) {
            #expect(en.solutionSQL == ru.solutionSQL)
            func executableStarter(_ sql: String) -> String { sql.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }.joined(separator: "\n") }
            #expect(executableStarter(en.starterSQL) == executableStarter(ru.starterSQL))
            #expect(en.validationSQL == ru.validationSQL)
            #expect(en.stateValidationSQL == ru.stateValidationSQL)
            #expect(en.fixtureIDs == ru.fixtureIDs)
            #expect(en.ordered == ru.ordered && en.columnNames == ru.columnNames)
            #expect(en.checkOutput == ru.checkOutput)
            #expect(en.outputOrdered == ru.outputOrdered)
            #expect(ru.title.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil, "Untranslated title: \(ru.id)")
            #expect(ru.prompt.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil, "Untranslated prompt: \(ru.id)")
            #expect(ru.hints.allSatisfy { $0.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil })
            #expect(ru.explanation.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil)
        }
        for lesson in russian.lessons {
            #expect(lesson.sections.count == 11)
            #expect(lesson.steps.first?.id == "\(lesson.id).read.0")
            #expect(lesson.steps.dropFirst().prefix(lesson.exercises.count).allSatisfy { $0.exercise != nil })
            #expect(lesson.steps.last?.id == "\(lesson.id).read.9")
            #expect(lesson.sections.allSatisfy { $0.body.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil })
        }
    }

    @Test func gradingFeedbackAndHistoricAttemptsTranslateWithoutChangingSQL() {
        let expected = QueryResult(columns: [QueryColumn(name: "customer_count", typeOID: 20)], rows: [["6"]], command: "", duration: 0)
        let actual = QueryResult(columns: expected.columns, rows: [], command: "", duration: 0)
        let english = ResultComparator.compare(actual: actual, expected: expected, ordered: false, columnNames: true)!
        let russian = ResultComparator.compare(actual: actual, expected: expected, ordered: false, columnNames: true, language: .russian)!
        #expect(russian.hasPrefix("Ожидалось"))
        #expect(CoreText.message(english, language: .russian) == russian)
        #expect(CoreText.message("Correct across all 2 datasets. Row order was checked.", language: .russian).contains("Верно"))
        #expect(CoreText.message("Column names must be customer_count. Check your aliases and column order.", language: .russian).contains("customer_count"))
    }

    @Test func readingFlowUpgradePreservesBookmarksDraftsAndExerciseCompletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-Migration-\(UUID().uuidString)").appendingPathComponent("progress.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try ProgressStore(url: url)
        var read = StepProgress(); read.completed = true; read.visits = 2
        var syntax = StepProgress(); syntax.completed = true; syntax.bookmarked = true; syntax.review = true
        try store.save(read, for: "l001.read.0"); try store.save(syntax, for: "l001.read.3"); try store.save(read, for: "l001.read.5")
        try store.save(read, for: "l001-e1"); try store.saveDraft("SELECT id FROM customers;", for: "l001.read.3")
        try store.setPosition("l001.read.3")
        try store.migrateReadingSteps(lessonIDs: ["l001"])
        let merged = try store.allProgress()["l001.read.0"]
        #expect(merged?.completed == true && merged?.bookmarked == true && merged?.review == true)
        #expect(try store.allProgress()["l001-e1"]?.completed == true)
        #expect(try store.drafts()["l001.read.0"] == "SELECT id FROM customers;")
        #expect(try store.position() == "l001.read.0")
        try store.migrateReadingSteps(lessonIDs: ["l001"])
        #expect(try store.allProgress()["l001.read.0"]?.visits == merged?.visits)
        #expect(try store.allProgress()["l001.read.3"] != nil)
    }

    @Test func importingOldReadingStepsMapsBookmarksWithoutLosingCurrentProgress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-OldBackup-\(UUID().uuidString)").appendingPathComponent("progress.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try ProgressStore(url: url)
        try store.migrateReadingSteps(lessonIDs: ["l001"])
        var old = StepProgress(); old.completed = true; old.bookmarked = true; old.review = true; old.visits = 2
        let backup = ProgressBackup(formatVersion: 1, exportedAt: Date(), progress: ["l001.read.3": old], attempts: [], drafts: ["l001.read.3": "SELECT 7;"], position: "l001.read.3")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.importData(encoder.encode(backup))
        let mapped = try #require(store.allProgress()["l001.read.0"])
        #expect(mapped.bookmarked && mapped.review && !mapped.completed)
        #expect(try store.drafts()["l001.read.0"] == "SELECT 7;")
        #expect(try store.position() == "l001.read.0")
        let exported = try JSONSerialization.jsonObject(with: store.exportData()) as! [String: Any]
        #expect(exported["courseFlowVersion"] as? Int == 2)
    }
}
