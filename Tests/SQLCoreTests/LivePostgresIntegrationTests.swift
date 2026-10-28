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

private enum LiveIntegrationTimeout: Error { case exceeded }

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
    func record(_ sql: String) { queries.append(sql) }
}

/// These integration checks exercise coalescing around actual PostgreSQL actor
/// calls and its hard deadline; the lightweight controller unit tests use fakes.
@Suite(.serialized)
struct LivePostgresIntegrationTests {
    private func waitFor(_ predicate: @escaping @Sendable () async -> Bool, seconds: Int = 10) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(seconds))
        while !(await predicate()) {
            if clock.now >= deadline { throw LiveIntegrationTimeout.exceeded }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func supersededRealQueryTimesOutAndLatestStepUsesItsOwnFixture() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-LiveDeadline-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let controller = LiveQueryController(engine: engine, delay: .milliseconds(10))
        let probe = LivePostgresProbe()
        do {
            try await engine.start()
            let began = ContinuousClock.now
            await controller.submit(sql: "SET statement_timeout=0; SELECT pg_sleep(20);", fixture: "", context: "old-step", revision: 1) { await probe.observe($0) }
            try await waitFor { await probe.hasStarted("old-step") }
            // The database call is already running. Only the newest pending
            // edit should survive while the engine enforces its hard deadline.
            for revision in 2...15 {
                await controller.submit(
                    sql: "SELECT sum(value) AS total FROM items;",
                    fixture: "CREATE TABLE items(value integer); INSERT INTO items VALUES (7),(8);",
                    context: revision == 15 ? "next-step" : "intermediate-\(revision)",
                    revision: UInt64(revision)
                ) { await probe.observe($0) }
            }
            try await waitFor { await probe.hasResult("next-step") }
            #expect(await probe.resultContexts() == ["next-step"])
            #expect(await probe.failureContexts().isEmpty)
            #expect(await probe.firstRows() == [["15"]])
            #expect(began.duration(to: .now) < .seconds(10))
            await controller.cancel(revision: 16)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
        } catch {
            await controller.cancel(revision: 16)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }

    @Test func cancellationSuppressesAnActualBackendResultAndRejectsLateClientEdits() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-LiveCancellation-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        let controller = LiveQueryController(engine: engine, delay: .milliseconds(10))
        let probe = LivePostgresProbe()
        do {
            try await engine.start()
            await controller.submit(sql: "SELECT pg_sleep(0.25); SELECT 'old' AS value;", fixture: "", context: "cancelled", revision: 1) { await probe.observe($0) }
            try await waitFor { await probe.hasStarted("cancelled") }
            await controller.cancel(revision: 3)
            await controller.submit(sql: "SELECT 'late' AS value;", fixture: "", context: "late", revision: 2) { await probe.observe($0) }
            try await Task.sleep(for: .milliseconds(450))
            #expect(await probe.resultContexts().isEmpty)
            #expect(await probe.failureContexts().isEmpty)
            await controller.submit(sql: "SELECT 'current' AS value;", fixture: "", context: "current", revision: 4) { await probe.observe($0) }
            try await waitFor { await probe.hasResult("current") }
            #expect(await probe.resultContexts() == ["current"])
            #expect(await probe.firstRows() == [["current"]])
            await controller.cancel(revision: 5)
            await engine.stop()
            try? FileManager.default.removeItem(at: base)
        } catch {
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
            await controller.submit(sql: "SELECT 'pending' AS value;", fixture: "", context: "pending", revision: 1) { await probe.observe($0) }
            await controller.shutdown()
            // Tasks already queued by the UI can arrive after shutdown. They
            // must be rejected even with a newer revision.
            await controller.submit(sql: "SELECT 'late' AS value;", fixture: "", context: "late", revision: 50) { await probe.observe($0) }
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
            try await waitFor { await probe.hasStarted("obsolete") }
            await controller.submit(sql: currentSQL, fixture: "", context: "current", revision: 2) { await probe.observe($0) }
            await gate.open()
            try await waitFor { await probe.hasResult("current") }
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
