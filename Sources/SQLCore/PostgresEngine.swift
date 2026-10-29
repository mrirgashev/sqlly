import Foundation
import CPQShim
import Darwin

public struct QueryColumn: Codable, Equatable, Sendable {
    public var name: String
    public var typeOID: UInt32
    public init(name: String, typeOID: UInt32) { self.name = name; self.typeOID = typeOID }
}

public struct QueryResult: Codable, Equatable, Sendable {
    public var columns: [QueryColumn]
    public var rows: [[String?]]
    public var command: String
    public var duration: Double
    public init(columns: [QueryColumn], rows: [[String?]], command: String, duration: Double) {
        self.columns = columns; self.rows = rows; self.command = command; self.duration = duration
    }
}

public struct PostgresError: Error, LocalizedError, Sendable {
    public enum Origin: Sendable, Equatable {
        case system
        case submittedStatement
        case validation
    }
    public var message: String
    public var sqlState: String
    public var origin: Origin
    public init(_ message: String, sqlState: String = "", origin: Origin = .system) {
        self.message = message; self.sqlState = sqlState; self.origin = origin
    }
    public var errorDescription: String? { message }
}

public struct ValidatedExecution: Sendable {
    public let output: QueryResult
    public let state: QueryResult
}

/// Owns a private, socket-only PostgreSQL cluster. Each run gets a new database.
/// Application progress is stored separately and is never accessible to learner SQL.
public actor PostgresEngine {
    public static let version = "18.6"
    private let baseURL: URL
    private let runtimeURL: URL?
    private var sessionURL: URL?
    private var socketURL: URL?
    private var server: Process?
    private var logHandle: FileHandle?
    private var port: Int = 0
    private var administrator = ""
    private var adminPassword = ""
    private var learnerPassword = ""
    private var isShutdown = false

    public init(baseURL: URL? = nil, runtimeURL: URL? = nil) {
        self.baseURL = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QueryCraft/Engine", isDirectory: true)
        self.runtimeURL = runtimeURL ?? SQLLYResources.postgresRuntime(in: SQLLYResources.coreBundle)
    }

    public func start() throws {
        guard !isShutdown else { throw PostgresError("The practice engine is shutting down.") }
        if let server, server.isRunning { return }
        let fm = FileManager.default
        guard let runtimeURL, SQLLYResources.isCompleteRuntime(runtimeURL) else {
            throw PostgresError("The bundled PostgreSQL runtime is missing. Rebuild with scripts/build-postgres.sh, then scripts/build-app.sh.")
        }
        let bin = runtimeURL.appendingPathComponent("bin")
        guard qc_load_postgres(runtimeURL.appendingPathComponent("lib/libpq.5.dylib").path) == 1 else {
            throw PostgresError("Cannot load the bundled PostgreSQL client: \(String(cString: qc_load_error()))")
        }
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
        recoverAbandonedSessions()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let session = baseURL.appendingPathComponent("session-\(token)", isDirectory: true)
        try fm.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        sessionURL = session
        try String(ProcessInfo.processInfo.processIdentifier).write(to: session.appendingPathComponent("owner.pid"), atomically: true, encoding: .utf8)
        // Unix-domain socket paths are limited to 104 bytes on macOS. The random,
        // private /tmp directory is the socket only; database data remains durable.
        let socket = URL(fileURLWithPath: "/tmp/qc-\(String(token.prefix(16)))", isDirectory: true)
        try fm.createDirectory(at: socket, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        socketURL = socket
        try socket.path.write(to: session.appendingPathComponent("socket.path"), atomically: true, encoding: .utf8)
        administrator = "qc_admin_\(String(token.prefix(12)))"
        adminPassword = UUID().uuidString + UUID().uuidString
        learnerPassword = UUID().uuidString + UUID().uuidString
        port = Int.random(in: 20_000...60_000) // No TCP listener; socket filename only.
        let pw = session.appendingPathComponent("init-password")
        try adminPassword.write(to: pw, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pw.path)
        let data = session.appendingPathComponent("data", isDirectory: true)
        do {
            try runUtility("initdb", arguments: ["-D", data.path, "-U", administrator, "-A", "scram-sha-256", "--pwfile", pw.path, "--encoding=UTF8", "--locale=C", "--no-instructions"], log: session.appendingPathComponent("initdb.log"))
            try? fm.removeItem(at: pw)
            let configuration = """
            listen_addresses = ''
            unix_socket_directories = '\(socket.path)'
            unix_socket_permissions = 0700
            port = \(port)
            max_connections = 12
            shared_buffers = '32MB'
            work_mem = '4MB'
            maintenance_work_mem = '16MB'
            temp_file_limit = '64MB'
            max_parallel_workers_per_gather = 0
            max_parallel_workers = 0
            max_worker_processes = 0
            statement_timeout = '3000ms'
            lock_timeout = '1000ms'
            idle_in_transaction_session_timeout = '5000ms'
            transaction_timeout = '8000ms'
            timezone = 'UTC'
            datestyle = 'ISO, YMD'
            password_encryption = 'scram-sha-256'
            logging_collector = off
            log_min_messages = warning
            log_statement = 'none'
            log_min_error_statement = 'panic'
            autovacuum = off
            jit = off
            fsync = on
            full_page_writes = on
            """
            try configuration.write(to: data.appendingPathComponent("postgresql.conf"), atomically: true, encoding: .utf8)
            // No trust rules and no TCP authentication rules.
            try "local all all scram-sha-256\n".write(to: data.appendingPathComponent("pg_hba.conf"), atomically: true, encoding: .utf8)
            let log = session.appendingPathComponent("server.log")
            fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            logHandle = handle
            let process = Process()
            process.executableURL = bin.appendingPathComponent("postgres")
            process.arguments = ["-D", data.path]
            process.environment = utilityEnvironment
            process.standardOutput = handle; process.standardError = handle
            try process.run(); server = process
            var ready = false
            for _ in 0..<100 {
                if !process.isRunning { break }
                if (try? query("SELECT 1", database: "postgres", administrator: true, timeout: 1000)) != nil { ready = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard ready else {
                let diagnostic = (try? String(contentsOf: log, encoding: .utf8)) ?? "No server log available."
                throw PostgresError("PostgreSQL could not start. \(diagnostic.suffix(1600))")
            }
            _ = try query("CREATE ROLE learner LOGIN PASSWORD '\(learnerPassword)' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS; REVOKE ALL ON DATABASE postgres FROM PUBLIC; REVOKE ALL ON DATABASE template1 FROM PUBLIC;", database: "postgres", administrator: true)
        } catch {
            stop()
            throw error
        }
    }

    /// Runs one script against fresh fixture data. Only the final statement's
    /// result is returned, matching PostgreSQL's normal simple-query semantics.
    public func execute(sql: String, fixture: String, setup: String? = nil) throws -> QueryResult {
        try perform(sql: sql, fixture: fixture, setup: setup, verificationSQL: nil).output
    }

    /// Executes a data/schema change, then checks committed state using trusted
    /// validation SQL. Uncommitted work is rolled back when submission ends.
    public func validate(sql: String, fixture: String, verificationSQL: String) throws -> QueryResult {
        try perform(sql: sql, fixture: fixture, setup: nil, verificationSQL: verificationSQL).state
    }

    /// Retains the script output as well as its independently checked committed
    /// state, without executing a mutating submission a second time.
    public func validateDetailed(sql: String, fixture: String, verificationSQL: String) throws -> ValidatedExecution {
        try perform(sql: sql, fixture: fixture, setup: nil, verificationSQL: verificationSQL)
    }

    private func perform(sql: String, fixture: String, setup: String?, verificationSQL: String?) throws -> ValidatedExecution {
        guard sql.utf8.count <= 131_072 else { throw PostgresError("The editor limit is 128 KB. Reduce the script before running it.") }
        try start()
        try resetLearnerSettings()
        let name = "practice_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = try query("CREATE DATABASE \(name) TEMPLATE template0", database: "postgres", administrator: true)
        defer { _ = try? query("DROP DATABASE IF EXISTS \(name) WITH (FORCE)", database: "postgres", administrator: true, timeout: 5000) }
        _ = try query("REVOKE ALL ON DATABASE \(name) FROM PUBLIC; GRANT CONNECT,TEMPORARY ON DATABASE \(name) TO learner;", database: "postgres", administrator: true)
        _ = try query("ALTER SCHEMA public OWNER TO learner; REVOKE ALL ON SCHEMA public FROM PUBLIC; GRANT USAGE, CREATE ON SCHEMA public TO learner;", database: name, administrator: true)
        if !fixture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try query("SET ROLE learner; SET search_path = public, pg_catalog; \(fixture)", database: name, administrator: true, timeout: 5000)
        }
        // The learner login has no membership in the administrator role. RESET
        // ROLE cannot elevate it. All validation uses an independent connection.
        if let setup, !setup.isEmpty { _ = try query(setup, database: name, administrator: false) }
        let result = try query(sql, database: name, administrator: false, origin: .submittedStatement)
        if let verificationSQL {
            try resetLearnerSettings()
            return ValidatedExecution(output: result, state: try query(verificationSQL, database: name, administrator: false, origin: .validation))
        }
        return ValidatedExecution(output: result, state: result)
    }

    private func resetLearnerSettings() throws {
        // PostgreSQL allows a login to change its own password and USERSET
        // defaults even without CREATEROLE. Restore these before every operation
        // and trusted validation, so a practice script cannot poison later runs.
        _ = try query("ALTER ROLE learner PASSWORD '\(learnerPassword)'; ALTER ROLE learner RESET ALL;", database: "postgres", administrator: true)
    }

    private func query(_ sql: String, database: String, administrator isAdmin: Bool, timeout: Int = 4000, origin: PostgresError.Origin = .system) throws -> QueryResult {
        guard let socketURL else { throw PostgresError("The practice engine has not started.") }
        let user = isAdmin ? administrator : "learner"
        let password = isAdmin ? adminPassword : learnerPassword
        let connection = "host='\(socketURL.path)' port=\(port) dbname='\(database)' user='\(user)' password='\(password)' connect_timeout=2 application_name='SQLLY' options='-c search_path=public,pg_catalog -c client_min_messages=warning'"
        guard let pointer = qc_execute(connection, sql, Int32(timeout), 2000, 4_194_304) else { throw PostgresError("Cannot allocate query result.") }
        defer { qc_free_result(pointer) }
        let value = pointer.pointee
        guard value.status == 1 else {
            throw PostgresError(value.error.map { String(cString: $0) } ?? "PostgreSQL query failed.", sqlState: value.sqlstate.map { String(cString: $0) } ?? "", origin: origin)
        }
        var columns: [QueryColumn] = []
        for index in 0..<Int(value.column_count) {
            columns.append(QueryColumn(name: String(cString: value.column_names[index]!), typeOID: value.column_types[index]))
        }
        var rows: [[String?]] = []
        for row in 0..<Int(value.row_count) {
            rows.append((0..<Int(value.column_count)).map { column in
                value.rows[row]![column].map { String(cString: $0) }
            })
        }
        return QueryResult(columns: columns, rows: rows, command: value.command.map { String(cString: $0) } ?? "", duration: value.duration)
    }

    public func stop() {
        if let server, server.isRunning, let sessionURL {
            try? runUtility("pg_ctl", arguments: ["-D", sessionURL.appendingPathComponent("data").path, "-m", "immediate", "-w", "-t", "5", "stop"], log: sessionURL.appendingPathComponent("shutdown.log"))
            if server.isRunning { server.terminate() }
        }
        server = nil
        try? logHandle?.close(); logHandle = nil
        if let socketURL { try? FileManager.default.removeItem(at: socketURL) }
        if let sessionURL { try? FileManager.default.removeItem(at: sessionURL) }
        socketURL = nil; sessionURL = nil
        adminPassword = ""; learnerPassword = ""
    }

    /// Terminal app shutdown. Unlike stop(), this rejects queued requests that
    /// would otherwise initialize another server after the app has quit.
    public func shutdown() {
        isShutdown = true
        stop()
    }

    private var utilityEnvironment: [String: String] {
        // Never inherit PGHOST, PGOPTIONS, DYLD_* or locale settings from a shell.
        ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C", "TZ": "UTC"]
    }

    private func runUtility(_ tool: String, arguments: [String], log: URL) throws {
        guard let runtimeURL else {
            throw PostgresError("The bundled PostgreSQL runtime is missing. Rebuild with scripts/build-postgres.sh, then scripts/build-app.sh.")
        }
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        let process = Process(); process.executableURL = runtimeURL.appendingPathComponent("bin/\(tool)")
        process.arguments = arguments; process.environment = utilityEnvironment
        process.standardOutput = handle; process.standardError = handle
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostic = (try? String(contentsOf: log, encoding: .utf8)) ?? "No diagnostic available."
            throw PostgresError("\(tool) failed: \(diagnostic.suffix(2000))")
        }
    }

    private func recoverAbandonedSessions() {
        let fm = FileManager.default
        for folder in (try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? [] where folder.lastPathComponent.hasPrefix("session-") {
            guard let text = try? String(contentsOf: folder.appendingPathComponent("owner.pid"), encoding: .utf8), let pid = Int32(text), kill(pid, 0) != 0 else { continue }
            try? runUtility("pg_ctl", arguments: ["-D", folder.appendingPathComponent("data").path, "-m", "immediate", "-w", "-t", "3", "stop"], log: folder.appendingPathComponent("recovery.log"))
            if let socket = try? String(contentsOf: folder.appendingPathComponent("socket.path"), encoding: .utf8), socket.hasPrefix("/tmp/qc-"), !socket.dropFirst(8).contains("/") { try? fm.removeItem(atPath: socket) }
            try? fm.removeItem(at: folder)
        }
    }
}
