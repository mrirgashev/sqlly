import Foundation
import CSQLite

public struct StepProgress: Codable, Sendable, Equatable {
    public var completed = false
    public var review = false
    public var bookmarked = false
    public var visits = 0
    public var updatedAt = Date()
    public init() {}
}

public struct Attempt: Codable, Identifiable, Sendable {
    public enum SubmissionKind: String, Codable, Sendable {
        /// A code answer checked by the grader, including a candidate SQL error.
        case gradedCode
        case assessment
        /// Initialization, fixture/reference execution, storage or other service failure.
        case infrastructureFailure
    }

    public var id: UUID
    public var exerciseID: String
    public var sql: String
    public var passed: Bool
    public var feedback: String
    public var date: Date
    /// Missing in older progress/backup JSON. Unknown legacy outcomes remain nil
    /// and are retained in history, but cannot unlock a worked code solution.
    public var submissionKind: SubmissionKind?
    public init(exerciseID: String, sql: String, passed: Bool, feedback: String, submissionKind: SubmissionKind? = nil) {
        self.id = UUID(); self.exerciseID = exerciseID; self.sql = sql
        self.passed = passed; self.feedback = feedback; self.date = Date()
        self.submissionKind = submissionKind
    }
}

public struct ProgressBackup: Codable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var progress: [String: StepProgress]
    public var attempts: [Attempt]
    public var drafts: [String: String]
    public var position: String?
    public var courseFlowVersion: Int? = nil
}

public struct StorageFailure: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// SQLite WAL storage, one connection serialized by a lock. UI state is never in the exercise server.
public final class ProgressStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let url: URL
    public private(set) var recoveryNotice: String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static var applicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QueryCraft", isDirectory: true)
    }

    public init(url: URL = ProgressStore.applicationDirectory.appendingPathComponent("progress.sqlite")) throws {
        self.url = url
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try open()
        do { try migrate() }
        catch {
            let code = sqlite3_errcode(db)
            guard code == SQLITE_CORRUPT || code == SQLITE_NOTADB else { throw error }
            sqlite3_close(db); db = nil
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = url.appendingPathExtension("damaged-\(stamp)")
            try FileManager.default.moveItem(at: url, to: quarantine)
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: url.path + suffix)
                if FileManager.default.fileExists(atPath: side.path) {
                    try FileManager.default.moveItem(at: side, to: URL(fileURLWithPath: quarantine.path + suffix))
                }
            }
            recoveryNotice = "The progress database was damaged. It was preserved at \(quarantine.path). A new database was created; you can import an exported backup."
            try open(); try migrate()
        }
    }

    deinit { sqlite3_close(db) }

    private func open() throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw failure("Cannot open learning progress")
        }
        sqlite3_busy_timeout(db, 3000)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func failure(_ context: String) -> StorageFailure {
        StorageFailure(message: "\(context): \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "No connection")")
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure("Progress storage failed") }
    }

    private func migrate() throws {
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        let version = try values("PRAGMA user_version;").first.flatMap(Int.init) ?? 0
        guard version <= 1 else { throw StorageFailure(message: "Progress was created by a newer QueryCraft version. Update the app before opening this database.") }
        if version == 0 {
            try execute("BEGIN IMMEDIATE; CREATE TABLE progress (id TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE attempts (id TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE drafts (id TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE settings (id TEXT PRIMARY KEY, value TEXT NOT NULL); PRAGMA user_version=1; COMMIT;")
        }
    }

    private func values(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure("Cannot read progress") }
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let ptr = sqlite3_column_text(statement, 0) { result.append(String(cString: ptr)) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure("Cannot read progress rows") }
        return result
    }

    private func pairs(_ table: String) throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id,value FROM \(table)", -1, &statement, nil) == SQLITE_OK else { throw failure("Cannot read progress") }
        defer { sqlite3_finalize(statement) }
        var result: [String: String] = [:]
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let key = sqlite3_column_text(statement, 0), let value = sqlite3_column_text(statement, 1) {
                result[String(cString: key)] = String(cString: value)
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure("Cannot read progress rows") }
        return result
    }

    private func upsert(_ table: String, id: String, value: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO \(table)(id,value) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value", -1, &statement, nil) == SQLITE_OK else { throw failure("Cannot save progress") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("Cannot save progress") }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    private func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T { try decoder.decode(type, from: Data(value.utf8)) }

    public func allProgress() throws -> [String: StepProgress] {
        lock.lock(); defer { lock.unlock() }
        return try pairs("progress").mapValues { try decode(StepProgress.self, $0) }
    }

    public func save(_ progress: StepProgress, for id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try upsert("progress", id: id, value: encode(progress))
    }

    public func saveDraft(_ sql: String, for id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try upsert("drafts", id: id, value: sql)
    }

    public func drafts() throws -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return try pairs("drafts")
    }

    public func attempts() throws -> [Attempt] {
        lock.lock(); defer { lock.unlock() }
        return try values("SELECT value FROM attempts").map { try decode(Attempt.self, $0) }.sorted { $0.date > $1.date }
    }

    public func record(_ attempt: Attempt) throws {
        lock.lock(); defer { lock.unlock() }
        try upsert("attempts", id: attempt.id.uuidString, value: encode(attempt))
    }

    public func position() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try pairs("settings")["position"]
    }

    public func setPosition(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try upsert("settings", id: "position", value: id)
    }

    /// Maps the original multi-reading sequence onto introduction/practice/recap.
    /// Old rows remain in the database and exports; exercises are never changed.
    public func migrateReadingSteps(lessonIDs: [String]) throws {
        lock.lock(); defer { lock.unlock() }
        guard try pairs("settings")["flowVersion"] != "2" else { return }
        let existing = try allProgress()
        let oldDrafts = try drafts()
        try execute("BEGIN IMMEDIATE")
        do {
            for lesson in lessonIDs {
                let keys = [0, 3, 5].map { "\(lesson).read.\($0)" }
                let states = keys.compactMap { existing[$0] }
                guard !states.isEmpty else { continue }
                var merged = StepProgress()
                merged.completed = keys.allSatisfy { existing[$0]?.completed == true }
                merged.review = states.contains(where: \.review)
                merged.bookmarked = states.contains(where: \.bookmarked)
                merged.visits = states.reduce(0) { $0 + $1.visits }
                merged.updatedAt = states.map(\.updatedAt).max() ?? Date()
                try save(merged, for: keys[0])
                if oldDrafts[keys[0]] == nil, let draft = keys.dropFirst().compactMap({ oldDrafts[$0] }).first { try saveDraft(draft, for: keys[0]) }
            }
            if let old = try position(), old.hasSuffix(".read.3") || old.hasSuffix(".read.5") {
                try setPosition(String(old.dropLast()) + "0")
            }
            try upsert("settings", id: "flowVersion", value: "2")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func exportData() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        var snapshot = try ProgressBackup(formatVersion: 1, exportedAt: Date(), progress: allProgress(), attempts: attempts(), drafts: drafts(), position: position())
        snapshot.courseFlowVersion = try pairs("settings")["flowVersion"].flatMap(Int.init)
        return try encoder.encode(snapshot)
    }

    /// Merge is atomic. Completion/bookmarks/review are combined; existing drafts and position are preserved.
    @discardableResult public func importData(_ data: Data) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard data.count <= 50_000_000 else { throw StorageFailure(message: "Backup exceeds the 50 MB import limit.") }
        let backup = try decoder.decode(ProgressBackup.self, from: data)
        guard backup.formatVersion == 1 else { throw StorageFailure(message: "Unsupported backup format version \(backup.formatVersion).") }
        let current = try allProgress()
        let existingDrafts = try drafts()
        let existingPosition = try position()
        let existingAttemptIDs = Set(try attempts().map(\.id))
        try execute("BEGIN IMMEDIATE")
        do {
            for (id, incoming) in backup.progress {
                var merged = incoming
                if let local = current[id] {
                    merged.completed = local.completed || incoming.completed
                    merged.review = local.review || incoming.review
                    merged.bookmarked = local.bookmarked || incoming.bookmarked
                    merged.visits = max(local.visits, incoming.visits)
                    merged.updatedAt = max(local.updatedAt, incoming.updatedAt)
                }
                try save(merged, for: id)
            }
            for attempt in backup.attempts where !existingAttemptIDs.contains(attempt.id) { try record(attempt) }
            for (id, sql) in backup.drafts where existingDrafts[id] == nil { try saveDraft(sql, for: id) }
            if backup.courseFlowVersion != 2 {
                let legacyLessons = Set(backup.progress.keys.compactMap { key -> String? in
                    guard let range = key.range(of: ".read."), ["0", "3", "5"].contains(String(key[range.upperBound...])) else { return nil }
                    return String(key[..<range.lowerBound])
                })
                for lesson in legacyLessons {
                    let keys = [0, 3, 5].map { "\(lesson).read.\($0)" }
                    let incoming = keys.compactMap { backup.progress[$0] }
                    var merged = try allProgress()[keys[0]] ?? StepProgress()
                    merged.completed = (current[keys[0]]?.completed ?? false) || keys.allSatisfy { backup.progress[$0]?.completed == true }
                    merged.review = (current[keys[0]]?.review ?? false) || incoming.contains(where: \.review)
                    merged.bookmarked = (current[keys[0]]?.bookmarked ?? false) || incoming.contains(where: \.bookmarked)
                    merged.visits = max(current[keys[0]]?.visits ?? 0, incoming.reduce(0) { $0 + $1.visits })
                    merged.updatedAt = max(current[keys[0]]?.updatedAt ?? .distantPast, incoming.map(\.updatedAt).max() ?? .distantPast)
                    try save(merged, for: keys[0])
                    if existingDrafts[keys[0]] == nil, backup.drafts[keys[0]] == nil,
                       let draft = keys.dropFirst().compactMap({ backup.drafts[$0] }).first { try saveDraft(draft, for: keys[0]) }
                }
            }
            if existingPosition == nil, let position = backup.position {
                let mapped = backup.courseFlowVersion != 2 && (position.hasSuffix(".read.3") || position.hasSuffix(".read.5")) ? String(position.dropLast()) + "0" : position
                try setPosition(mapped)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        return backup.progress.count
    }
}
