import Foundation
import Testing
@testable import SQLCore

private actor LivePostgresProbe {
    private(set) var started: [String] = []
    private(set) var results: [(String, QueryResult)] = []
    private(set) var failures: [(String, String)] = []
    func observe(_ event: LiveQueryEvent) {
        switch event {
        case let .started(context): started.append(context)
        case let .result(context, result): results.append((context, result))
        case let .failure(context, message): failures.append((context, message))
        case .idle: break
        }
    }
    func hasStarted(_ context: String) -> Bool { started.contains(context) }
    func hasResult(_ context: String) -> Bool { results.contains { $0.0 == context } }
    func resultContexts() -> [String] { results.map(\.0) }
    func firstRows() -> [[String?]]? { results.first?.1.rows }
    func failureContexts() -> [String] { failures.map(\.0) }
}

private enum LiveIntegrationTimeout: Error { case exceeded(String) }

private extension LiveQueryController {
    /// Reproduce one uninterrupted client turn, independent of runner load.
    func receiveIntegrationBurst(_ actions: @Sendable (isolated LiveQueryController) -> Void) {
        actions(self)
    }
}

private actor LiveObserverGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor LiveExecutorHistory {
    private(set) var queries: [String] = []
    private var successes: [String: QueryResult] = [:]
    private var failures: [String: PostgresError] = [:]
    func record(_ sql: String) { queries.append(sql) }
    func succeeded(_ sql: String, result: QueryResult) { successes[sql] = result }
    func failed(_ sql: String, error: any Error) {
        failures[sql] = error as? PostgresError ?? PostgresError(error.localizedDescription)
    }
    func hasFinished(_ sql: String) -> Bool { successes[sql] != nil || failures[sql] != nil }
    func result(for sql: String) -> QueryResult? { successes[sql] }
    func failure(for sql: String) -> PostgresError? { failures[sql] }
}

/// These integration checks exercise coalescing around actual PostgreSQL actor
/// calls and its hard deadline; the lightweight controller unit tests use fakes.
@Suite(.serialized)
struct LivePostgresIntegrationTests {
    private func waitFor(_ description: String, _ predicate: @escaping @Sendable () async -> Bool, seconds: Int = 30) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(seconds))
        while !(await predicate()) {
            if clock.now >= deadline { throw LiveIntegrationTimeout.exceeded(description) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Hold the completed backend response before the controller can publish it.
    /// Waiting for `.started` alone is insufficient: observer delivery is an
    /// actor hop, and a busy runner may resume the test after execution finishes.
    private func gatedController(engine: PostgresEngine, history: LiveExecutorHistory,
                                 gate: LiveObserverGate, heldSQL: String) -> LiveQueryController {
        LiveQueryController(delay: .milliseconds(10)) { sql, fixture in
            await history.record(sql)
            do {
                let result = try await engine.execute(sql: sql, fixture: fixture)
                await history.succeeded(sql, result: result)
                if sql == heldSQL { await gate.wait() }
                return result
            } catch {
                await history.failed(sql, error: error)
                if sql == heldSQL { await gate.wait() }
                throw error
            }
        }
    }

    @Test func supersededRealQueryTimesOutAndLatestStepUsesItsOwnFixture() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-LiveDeadline-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let history = LiveExecutorHistory()
        let gate = LiveObserverGate()
        let oldSQL = "SET statement_timeout=0; SELECT pg_sleep(20);"
        let latestSQL = "SELECT sum(value) AS total FROM items;"
        let controller = gatedController(engine: engine, history: history, gate: gate, heldSQL: oldSQL)
        let probe = LivePostgresProbe()
        do {
            try await engine.start()
            await controller.submit(sql: oldSQL, fixture: "", context: "old-step", revision: 1) { await probe.observe($0) }
            try await waitFor("the obsolete backend's actual timeout") { await history.hasFinished(oldSQL) }
            let timeout = try #require(await history.failure(for: oldSQL))
            #expect(timeout.sqlState == "57014")
            #expect(timeout.message.contains("Query exceeded the practice time limit."))
            // The actual hard-deadline error exists and is held before delivery.
            // Only the newest pending edit may execute after it is superseded.
            await controller.receiveIntegrationBurst { controller in
                for revision in 2...15 {
                    controller.submit(
                        sql: latestSQL,
                        fixture: "CREATE TABLE items(value integer); INSERT INTO items VALUES (7),(8);",
                        context: revision == 15 ? "next-step" : "intermediate-\(revision)",
                        revision: UInt64(revision)
                    ) { await probe.observe($0) }
                }
            }
            await gate.open()
            try await waitFor("the latest step's fixture result") { await probe.hasResult("next-step") }
            #expect(await history.queries == [oldSQL, latestSQL])
            #expect(await probe.resultContexts() == ["next-step"])
            #expect(await probe.failureContexts().isEmpty)
            #expect(await probe.firstRows() == [["15"]])
            await controller.cancel(revision: 16)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
        } catch {
            await gate.open()
            await controller.cancel(revision: 16)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func cancellationSuppressesAnActualBackendResultAndRejectsLateClientEdits() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-LiveCancellation-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let history = LiveExecutorHistory()
        let gate = LiveObserverGate()
        let cancelledSQL = "SELECT 'old' AS value;"
        let currentSQL = "SELECT 'current' AS value;"
        let controller = gatedController(engine: engine, history: history, gate: gate, heldSQL: cancelledSQL)
        let probe = LivePostgresProbe()
        do {
            try await engine.start()
            await controller.submit(sql: cancelledSQL, fixture: "", context: "cancelled", revision: 1) { await probe.observe($0) }
            try await waitFor("the cancelled request's real backend result") { await history.hasFinished(cancelledSQL) }
            #expect(await history.result(for: cancelledSQL)?.rows == [["old"]])
            #expect(await history.failure(for: cancelledSQL) == nil)
            await controller.receiveIntegrationBurst { controller in
                controller.cancel(revision: 3)
                controller.submit(sql: "SELECT 'late' AS value;", fixture: "", context: "late", revision: 2) { await probe.observe($0) }
            }
            #expect(await probe.resultContexts().isEmpty)
            #expect(await probe.failureContexts().isEmpty)
            await controller.submit(sql: currentSQL, fixture: "", context: "current", revision: 4) { await probe.observe($0) }
            await gate.open()
            try await waitFor("the current request's published result") { await probe.hasResult("current") }
            #expect(await history.queries == [cancelledSQL, currentSQL])
            #expect(await probe.resultContexts() == ["current"])
            #expect(await probe.failureContexts().isEmpty)
            #expect(await probe.firstRows() == [["current"]])
            await controller.cancel(revision: 5)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
        } catch {
            await gate.open()
            await controller.cancel(revision: 5)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func terminalShutdownRejectsDeferredWorkAndCannotRestartPostgres() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-TerminalShutdown-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let controller = LiveQueryController(engine: engine, delay: .milliseconds(100))
        let probe = LivePostgresProbe()
        do {
            try await engine.start()
            await controller.receiveIntegrationBurst { controller in
                controller.submit(sql: "SELECT 'pending' AS value;", fixture: "", context: "pending", revision: 1) { await probe.observe($0) }
                controller.shutdown()
                // Tasks already queued by the UI can arrive after shutdown.
                // They must be rejected even with a newer revision.
                controller.submit(sql: "SELECT 'late' AS value;", fixture: "", context: "late", revision: 50) { await probe.observe($0) }
            }
            try await Task.sleep(for: .milliseconds(180))
            #expect(await probe.started.isEmpty)
            #expect(await probe.resultContexts().isEmpty)
            await engine.shutdown()
            await #expect(throws: (any Error).self) { try await engine.start() }
            await #expect(throws: (any Error).self) { try await engine.execute(sql: "SELECT 1", fixture: "") }
            // Restartable stop() is deliberately a different API; calling it
            // after terminal shutdown cannot clear the terminal state.
            await engine.stop()
            await #expect(throws: (any Error).self) { try await engine.start() }
            #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
            try? FileManager.default.removeItem(at: base)
        } catch {
            await controller.shutdown()
            await engine.shutdown()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func supersedingDuringStartedObserverDoesNotExecuteTheObsoleteDraft() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-LiveObserver-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let gate = LiveObserverGate()
        let history = LiveExecutorHistory()
        let probe = LivePostgresProbe()
        let controller = LiveQueryController(delay: .milliseconds(10)) { sql, fixture in
            await history.record(sql)
            return try await engine.execute(sql: sql, fixture: fixture)
        }
        let currentSQL = "SELECT 'current' AS value;"
        do {
            try await engine.start()
            await controller.submit(sql: "SELECT 'obsolete' AS value;", fixture: "", context: "obsolete", revision: 1) { event in
                await probe.observe(event)
                // UI delivery is another actor hop. A newer edit can arrive
                // while this observer is suspended, before execution begins.
                if case let .started(context) = event, context == "obsolete" { await gate.wait() }
            }
            try await waitFor("the obsolete request's held observer") { await probe.hasStarted("obsolete") }
            await controller.submit(sql: currentSQL, fixture: "", context: "current", revision: 2) { await probe.observe($0) }
            await gate.open()
            try await waitFor("the replacement request's result") { await probe.hasResult("current") }
            #expect(await history.queries == [currentSQL])
            #expect(await probe.resultContexts() == ["current"])
            #expect(await probe.firstRows() == [["current"]])
            await controller.shutdown()
            await engine.shutdown()
            try? FileManager.default.removeItem(at: base)
        } catch {
            await gate.open()
            await controller.shutdown()
            await engine.shutdown()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }
}
