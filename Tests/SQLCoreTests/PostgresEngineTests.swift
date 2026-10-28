import Foundation
import Testing
@testable import SQLCore

@Suite(.serialized)
struct PostgresEngineTests {
    private let fixture = """
    CREATE TABLE items(id integer PRIMARY KEY, label text, amount numeric(12,2));
    INSERT INTO items VALUES (1,'Tea',12.50),(2,'Tea',12.50),(3,NULL,NULL),(4,'Café, 雪',0.10);
    """

    private func withEngine(_ body: (PostgresEngine) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftTests-\(UUID().uuidString)")
        let engine = PostgresEngine(baseURL: base)
        do { try await body(engine); await engine.stop(); try? FileManager.default.removeItem(at: base) }
        catch { await engine.stop(); try? FileManager.default.removeItem(at: base); throw error }
    }

    @Test func realPostgresTypesNullsDuplicatesUnicode() async throws {
        try await withEngine { engine in
            let result = try await engine.execute(sql: "SELECT label, amount FROM items ORDER BY id", fixture: fixture)
            #expect(result.columns.map(\.name) == ["label", "amount"])
            #expect(result.columns.map(\.typeOID) == [25, 1700])
            #expect(result.rows == [["Tea", "12.50"], ["Tea", "12.50"], [nil, nil], ["Café, 雪", "0.10"]])
            let version = try await engine.execute(sql: "SHOW server_version", fixture: "")
            #expect(version.rows.first?.first == "18.6")
        }
    }

    @Test func finalStatementAndSafeDMLValidation() async throws {
        try await withEngine { engine in
            let result = try await engine.execute(sql: "BEGIN; UPDATE items SET amount=1 WHERE id=1; COMMIT; SELECT amount FROM items WHERE id=1", fixture: fixture)
            #expect(result.rows == [["1.00"]])
            let modified = try await engine.validate(sql: "DELETE FROM items WHERE amount IS NULL", fixture: fixture, verificationSQL: "SELECT count(*) FROM items")
            #expect(modified.rows == [["3"]])
            let schema = try await engine.validate(sql: "CREATE TABLE archive(id integer PRIMARY KEY, amount numeric CHECK(amount>=0)); INSERT INTO archive VALUES(1,8)", fixture: "", verificationSQL: "SELECT id,amount FROM archive")
            #expect(schema.rows == [["1","8"]])
        }
    }

    @Test func datasetsResetAfterDestructiveQueriesAndErrors() async throws {
        try await withEngine { engine in
            _ = try await engine.execute(sql: "DROP SCHEMA public CASCADE", fixture: fixture)
            let fresh = try await engine.execute(sql: "SELECT count(*) FROM items", fixture: fixture)
            #expect(fresh.rows == [["4"]])
            do { _ = try await engine.execute(sql: "SELEC * FROM items", fixture: fixture); Issue.record("Invalid SQL unexpectedly succeeded") }
            catch let error as PostgresError { #expect(error.sqlState == "42601") }
            let afterError = try await engine.execute(sql: "SELECT count(*) FROM items", fixture: fixture)
            #expect(afterError.rows == [["4"]])
        }
    }

    @Test func privilegeBoundaries() async throws {
        try await withEngine { engine in
            let role = try await engine.execute(sql: "SELECT current_user, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname=current_user", fixture: "")
            #expect(role.rows == [["learner","f","f","f"]])
            let forbidden = [
                "CREATE ROLE intruder SUPERUSER", "CREATE DATABASE intruder", "ALTER ROLE learner SUPERUSER",
                "SELECT pg_read_file('/etc/passwd')", "COPY (SELECT 1) TO PROGRAM 'touch /tmp/querycraft-unsafe'",
                "SELECT rolpassword FROM pg_authid", "CREATE EXTENSION file_fdw"
            ]
            for sql in forbidden {
                do { _ = try await engine.execute(sql: sql, fixture: ""); Issue.record("Forbidden SQL unexpectedly succeeded: \(sql)") }
                catch let error as PostgresError { #expect(!error.message.isEmpty) }
            }
            let afterResetRole = try await engine.execute(sql: "RESET ROLE; SELECT current_user", fixture: "")
            #expect(afterResetRole.rows == [["learner"]])
        }
    }

    @Test func hardTimeoutCannotBeDisabledByLearner() async throws {
        try await withEngine { engine in
            let start = Date()
            do { _ = try await engine.execute(sql: "SET statement_timeout=0; SELECT pg_sleep(20)", fixture: ""); Issue.record("Timeout did not fire") }
            catch let error as PostgresError { #expect(error.sqlState == "57014") }
            #expect(Date().timeIntervalSince(start) < 10)
            let after = try await engine.execute(sql: "SELECT 42 AS answer", fixture: "")
            #expect(after.rows == [["42"]])
        }
    }

    @Test func resultAndStatementLimits() async throws {
        try await withEngine { engine in
            do { _ = try await engine.execute(sql: "SELECT generate_series(1,2001)", fixture: ""); Issue.record("Row cap did not fire") }
            catch let error as PostgresError { #expect(error.sqlState == "54000") }
            do { _ = try await engine.execute(sql: "SELECT repeat('x',4194305)", fixture: ""); Issue.record("Byte cap did not fire") }
            catch let error as PostgresError { #expect(error.sqlState == "54000") }
            let boundary = try await engine.execute(sql: "SELECT generate_series(1,2000)", fixture: "")
            #expect(boundary.rows.count == 2000)
        }
    }

    @Test func fullPostgresAdvancedFeatures() async throws {
        try await withEngine { engine in
            let windows = try await engine.execute(sql: "SELECT id, sum(id) OVER (ORDER BY id) FROM items ORDER BY id", fixture: fixture)
            #expect(windows.rows == [["1","1"],["2","3"],["3","6"],["4","10"]])
            let recursion = try await engine.execute(sql: "WITH RECURSIVE n AS (SELECT 1 AS x UNION ALL SELECT x+1 FROM n WHERE x<3) SELECT x FROM n ORDER BY x", fixture: "")
            #expect(recursion.rows == [["1"],["2"],["3"]])
            let json = try await engine.execute(sql: "SELECT '{\"name\":\"Tea\"}'::jsonb->>'name', ARRAY[1,2] @> ARRAY[2], to_tsvector('english','running') @@ plainto_tsquery('english','run')", fixture: "")
            #expect(json.rows == [["Tea","t","t"]])
            let plpgsql = try await engine.execute(sql: "CREATE FUNCTION twice(x integer) RETURNS integer LANGUAGE plpgsql AS $$ BEGIN RETURN x*2; END $$; SELECT twice(4)", fixture: "")
            #expect(plpgsql.rows == [["8"]])
        }
    }

    @Test func concurrentSubmissionsRemainIsolated() async throws {
        try await withEngine { engine in
            let results = try await withThrowingTaskGroup(of: QueryResult.self) { group in
                group.addTask { try await engine.execute(sql: "DROP TABLE items; SELECT 1 AS job", fixture: fixture) }
                group.addTask { try await engine.execute(sql: "UPDATE items SET amount=99; SELECT count(*) AS job FROM items", fixture: fixture) }
                var values: [QueryResult] = []
                for try await result in group { values.append(result) }
                return values
            }
            #expect(results.compactMap { $0.rows.first?.first ?? nil }.sorted() == ["1", "4"])
            let unchanged = try await engine.execute(sql: "SELECT amount FROM items WHERE id=1", fixture: fixture)
            #expect(unchanged.rows == [["12.50"]])
        }
    }

    @Test func interruptedTransactionsAndRoleSettingsDoNotPoisonLaterRuns() async throws {
        try await withEngine { engine in
            let rollback = try await engine.validate(sql: "BEGIN; UPDATE items SET amount=99 WHERE id=1", fixture: fixture, verificationSQL: "SELECT amount FROM items WHERE id=1")
            #expect(rollback.rows == [["12.50"]])
            _ = try await engine.execute(sql: "ALTER ROLE learner PASSWORD 'practice'; ALTER ROLE learner SET search_path = nonexistent", fixture: "")
            let restored = try await engine.execute(sql: "SELECT count(*) FROM items", fixture: fixture)
            #expect(restored.rows == [["4"]])
            await engine.stop()
            let restarted = try await engine.execute(sql: "SELECT amount FROM items WHERE id=1", fixture: fixture)
            #expect(restarted.rows == [["12.50"]])
        }
    }

    @Test func abandonedClusterIsStoppedAndReplacedOnStartup() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QueryCraftCrash-\(UUID().uuidString)")
        let abandoned = PostgresEngine(baseURL: base)
        let replacement = PostgresEngine(baseURL: base)
        do {
            _ = try await abandoned.execute(sql: "SELECT 1", fixture: "")
            let folders = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            let old = try #require(folders.first { $0.lastPathComponent.hasPrefix("session-") })
            // Simulate a crashed GUI's stale owner record, while retaining the
            // process handle so the test can always clean up on failure.
            try String(Int32.max).write(to: old.appendingPathComponent("owner.pid"), atomically: true, encoding: .utf8)
            let result = try await replacement.execute(sql: "SELECT 2", fixture: "")
            #expect(result.rows == [["2"]])
            #expect(!FileManager.default.fileExists(atPath: old.path))
            let active = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("session-") }
            #expect(active.count == 1)
            await abandoned.stop(); await replacement.stop()
            try? FileManager.default.removeItem(at: base)
        } catch {
            await abandoned.stop(); await replacement.stop()
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }
}
