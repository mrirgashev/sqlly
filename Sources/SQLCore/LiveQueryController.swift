import Foundation

public enum LiveQueryEvent: Sendable {
    case started(context: String)
    case result(context: String, QueryResult)
    case failure(context: String, String)
    case idle
}

/// Debounces edits and coalesces work into one running request and one latest
/// pending request. Old results are never published after another edit or step.
/// Execution stays in disposable PostgreSQL datasets and never invokes grading.
public actor LiveQueryController {
    public typealias Executor = @Sendable (String, String) async throws -> QueryResult
    public typealias Observer = @Sendable (LiveQueryEvent) async -> Void
    private struct Request: Sendable {
        let generation: UInt64
        let context: String
        let sql: String
        let fixture: String
        let observer: Observer
    }
    private let execute: Executor
    private let delay: Duration
    private var generation: UInt64 = 0
    private var debounce: Task<Void, Never>?
    private var pending: Request?
    private var running = false
    private var lastClientRevision: UInt64 = 0
    private var closed = false

    public init(engine: PostgresEngine, delay: Duration = .milliseconds(600)) {
        self.execute = { sql, fixture in try await engine.execute(sql: sql, fixture: fixture) }
        self.delay = delay
    }

    public init(delay: Duration = .milliseconds(600), execute: @escaping Executor) {
        self.execute = execute
        self.delay = delay
    }

    public func submit(sql: String, fixture: String, context: String, revision: UInt64? = nil, observer: @escaping Observer) {
        guard !closed else { return }
        if let revision {
            guard revision > lastClientRevision else { return }
            lastClientRevision = revision
        }
        generation &+= 1
        debounce?.cancel()
        pending = nil
        let request = Request(generation: generation, context: context, sql: sql, fixture: fixture, observer: observer)
        debounce = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.ready(request)
        }
    }

    /// An already-running PostgreSQL statement remains bounded by the engine's
    /// hard deadline. Its stale result is suppressed rather than queued in UI.
    public func cancel(revision: UInt64? = nil) {
        if let revision {
            guard revision >= lastClientRevision else { return }
            lastClientRevision = revision
        }
        generation &+= 1
        debounce?.cancel(); debounce = nil; pending = nil
    }

    public func shutdown() {
        closed = true
        generation &+= 1
        debounce?.cancel(); debounce = nil; pending = nil
    }

    private func ready(_ request: Request) {
        guard !closed, request.generation == generation else { return }
        pending = request
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        while !closed, let request = pending {
            pending = nil
            guard request.generation == generation else { continue }
            await request.observer(.started(context: request.context))
            guard !closed, request.generation == generation else { continue }
            do {
                let result = try await execute(request.sql, request.fixture)
                if request.generation == generation {
                    await request.observer(.result(context: request.context, result))
                }
            } catch {
                if request.generation == generation {
                    await request.observer(.failure(context: request.context, error.localizedDescription))
                }
            }
        }
        running = false
    }
}
