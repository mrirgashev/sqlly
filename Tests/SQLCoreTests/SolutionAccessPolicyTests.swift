import Foundation
import Testing
@testable import SQLCore

struct SolutionAccessPolicyTests {
    private func attempt(_ sql: String, exerciseID: String = "target", passed: Bool = false,
                         kind: Attempt.SubmissionKind? = .gradedCode) -> Attempt {
        Attempt(exerciseID: exerciseID, sql: sql, passed: passed, feedback: "Saved feedback", submissionKind: kind)
    }

    private func fingerprint(_ sql: String) -> String? { SolutionAccessPolicy.codeFingerprint(sql) }

    @Test func requiresTenDistinctFailedCodeAnswersEvenAfterSuccess() {
        let empty = SolutionAccessPolicy(exerciseID: "target", attempts: [])
        #expect(empty.distinctFailedCodeAttempts == 0 && empty.remainingAttempts == 10 && !empty.isUnlocked)
        var history = (1...9).map { attempt("SELECT \($0)") }
        history.append(attempt("SELECT 100", passed: true))
        let nine = SolutionAccessPolicy(exerciseID: "target", attempts: history)
        #expect(nine.distinctFailedCodeAttempts == 9 && nine.remainingAttempts == 1 && !nine.isUnlocked)
        history.append(attempt("SELECT 10"))
        let ten = SolutionAccessPolicy(exerciseID: "target", attempts: history)
        #expect(ten.distinctFailedCodeAttempts == 10 && ten.remainingAttempts == 0 && ten.isUnlocked)
        history.append(attempt("SELECT 11"))
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: history).remainingAttempts == 0)
    }

    @Test func formattingCommentsAndUnquotedCaseNeverCreateExtraCredit() {
        let variants = [
            "SELECT id, name FROM customers WHERE id > 5;",
            "\n select ID , NAME from CUSTOMERS where id>5 \t",
            "SELECT/* note */id,name FROM customers -- ignore this\nWHERE id > 5;",
            "select /* outer /* nested */ final */ id, name from customers where id > 5;;;",
            ";;;SELECT id, name FROM customers WHERE id > 5; -- other note"
        ]
        #expect(Set(variants.compactMap(fingerprint)).count == 1)
        let history = variants.map { attempt($0) } + variants.map { attempt($0) }
        let policy = SolutionAccessPolicy(exerciseID: "target", attempts: history)
        #expect(policy.distinctFailedCodeAttempts == 1 && !policy.isUnlocked)
    }

    @Test func onlyThisExercisesFailedGradedCodeSubmissionsCount() {
        let history = [
            attempt("SELECT 1"),
            attempt("SELECT 2", exerciseID: "target-other"),
            attempt("SELECT 3", exerciseID: "TARGET"),
            attempt("SELECT 4", passed: true),
            attempt("SELECT 5", kind: .assessment),
            attempt("SELECT 6", kind: .infrastructureFailure),
            attempt("SELECT 7", kind: nil)
        ]
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: history).distinctFailedCodeAttempts == 1)
        #expect(SolutionAccessPolicy(exerciseID: "target-other", attempts: history).distinctFailedCodeAttempts == 1)
        #expect(SolutionAccessPolicy(exerciseID: "missing", attempts: history).distinctFailedCodeAttempts == 0)
    }

    @Test func blankCommentsAndEmptyStatementsNeverCount() {
        let blank = ["", " \t\r\n", "-- only a comment", "/* outer /* inner */ done */", ";;;", " ; /*x*/ ; -- end"]
        #expect(blank.allSatisfy { fingerprint($0) == nil })
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: blank.map { attempt($0) }).distinctFailedCodeAttempts == 0)
        #expect(fingerprint("SELECT 1 /* unfinished comment") == fingerprint("select 1"))
    }

    @Test func quotedValuesAndIdentifiersPreserveCaseSpacingAndCommentMarkers() {
        let original = #"SELECT 'O''Reilly -- /* value */', "MiX" FROM catalog;"#
        let formatted = #"select 'O''Reilly -- /* value */', "MiX" from CATALOG"#
        #expect(fingerprint(original) == fingerprint(formatted))
        #expect(fingerprint(original) != fingerprint(#"SELECT 'o''Reilly -- /* value */', "MiX" FROM catalog"#))
        #expect(fingerprint(original) != fingerprint(#"SELECT 'O''Reilly -- /* value */', "mix" FROM catalog"#))
        #expect(fingerprint("SELECT 'two  spaces'") != fingerprint("SELECT 'two spaces'"))
        #expect(fingerprint(#"SELECT "a""B" FROM t"#) != fingerprint(#"SELECT "a""b" FROM t"#))
        #expect(fingerprint("SELECT '--first'") != fingerprint("SELECT '--second'"))
    }

    @Test func escapeStringsKeepEscapedQuotesAndEmbeddedCommentsOpaque() {
        let original = #"SELECT E'can\'t -- /* content */', 'tail'; -- outside"#
        let formatted = #"select e'can\'t -- /* content */', 'tail' /* new outside */"#
        #expect(fingerprint(original) == fingerprint(formatted))
        #expect(fingerprint(original) != fingerprint(#"SELECT E'can\'t -- /* changed */', 'tail'"#))
        #expect(fingerprint(#"SELECT E'\\\'quoted'"#) == fingerprint(#"select e'\\\'quoted' -- end"#))
        #expect(fingerprint(#"SELECT E'abc'"#) != fingerprint(#"SELECT e 'abc'"#))
        #expect(fingerprint(#"SELECT '\', 'after--value'; -- outside"#) == fingerprint(#"select '\', 'after--value' /* outside */"#))
    }

    @Test func unicodeAndBitPrefixesAreRecognizedWithoutChangingQuotedBytes() {
        #expect(fingerprint(#"SELECT U&'d\0061ta', U&"MiX", B'101', X'FF', N'name'"#)
                == fingerprint(#"select u&'d\0061ta', u&"MiX", b'101', x'FF', n'name' -- note"#))
        #expect(fingerprint(#"SELECT U&"MiX""Name""#) != fingerprint(#"SELECT U&"mix""Name""#))
        #expect(fingerprint(#"SELECT U&'d\0061ta'"#) != fingerprint(#"SELECT U&'d\0061TA'"#))
    }

    @Test func dollarQuotedBodiesAreOpaqueAndTagsAreOnlyDelimiters() {
        let original = #"SELECT $Tag$Case -- /* content */ ' " $$ nested$Tag$, $σ$雪$σ$;"#
        let retagged = #"select $Other$Case -- /* content */ ' " $$ nested$Other$, $$雪$$ -- outside"#
        #expect(fingerprint(original) == fingerprint(retagged))
        #expect(fingerprint(original) != fingerprint(#"SELECT $Tag$case -- /* content */ ' " $$ nested$Tag$, $σ$雪$σ$"#))
        #expect(fingerprint("SELECT $$a b$$") != fingerprint("SELECT $$a  b$$"))
        #expect(fingerprint("SELECT $TAG$value$tag$") != fingerprint("SELECT $TAG$value$TAG$"))
        // A number can directly precede a dollar string; it is not an identifier.
        #expect(fingerprint("SELECT 1$$MiX$$") != fingerprint("SELECT 1$$mix$$"))
        #expect(fingerprint("SELECT foo$tag$value$tag$") == fingerprint("select FOO$TAG$VALUE$TAG$"))
    }

    @Test func tokenAndStatementBoundariesDoNotCollide() {
        #expect(fingerprint("SELECT a b") != fingerprint("SELECT ab"))
        #expect(fingerprint("SELECT 1,23") != fingerprint("SELECT 12,3"))
        #expect(fingerprint("SELECT 1; SELECT 2") != fingerprint("SELECT 1 SELECT 2"))
        #expect(fingerprint("SELECT 1; SELECT 2;") == fingerprint(";select 1;;;select 2;;;"))
        #expect(fingerprint("SELECT a>=5, a+-2, b::integer FROM t")
                == fingerprint("select A >= 5 , a + - 2 , B :: INTEGER from T"))
        #expect(fingerprint("SELECT a<=b") != fingerprint("SELECT a< =b"))
    }

    @Test func unicodeQuotedPayloadsRemainByteDistinct() {
        #expect(fingerprint("SELECT 'Café 雪 🧑🏽‍💻'") == fingerprint("select 'Café 雪 🧑🏽‍💻' -- note"))
        #expect(fingerprint("SELECT '\u{00e9}'") != fingerprint("SELECT 'e\u{0301}'"))
        #expect(fingerprint("SELECT \"\u{00e9}\"") != fingerprint("SELECT \"e\u{0301}\""))
        // PostgreSQL's UTF-8/C scanner folds ASCII letters, not multibyte names.
        #expect(fingerprint("SELECT ИМЯ FROM t") != fingerprint("SELECT имя FROM t"))
        #expect(fingerprint("SELECT имя FROM T") == fingerprint("select имя from t"))
    }

    @Test func unfinishedQuotesStayOpaqueRatherThanExposingComments() {
        #expect(fingerprint("SELECT 'text -- a") != fingerprint("SELECT 'text -- b"))
        #expect(fingerprint("SELECT $tag$/* a") != fingerprint("SELECT $tag$/* b"))
        #expect(fingerprint("SELECT \"text -- a") != fingerprint("SELECT \"text -- b"))
    }

    @Test func sourceLimitUsesUTF8Bytes() {
        let limit = SolutionAccessPolicy.maximumCodeBytes
        #expect(fingerprint(String(repeating: " ", count: limit - 8) + "SELECT 1") != nil)
        #expect(fingerprint(String(repeating: " ", count: limit - 7) + "SELECT 1") == nil)
        #expect(fingerprint(String(repeating: "é", count: limit / 2 + 1)) == nil)
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: [attempt(String(repeating: "x", count: limit + 1))]).distinctFailedCodeAttempts == 0)
    }

    @Test func repeatedUUIDsDoNotCountAndConflictingCopiesAreConservative() {
        let original = attempt("SELECT 1")
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: [original, original]).distinctFailedCodeAttempts == 1)
        var changed = original; changed.sql = "SELECT 2"
        let first = SolutionAccessPolicy(exerciseID: "target", attempts: [original, changed])
        let second = SolutionAccessPolicy(exerciseID: "target", attempts: [changed, original])
        #expect(first == second && first.distinctFailedCodeAttempts == 0)
        changed = original; changed.submissionKind = .infrastructureFailure
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: [original, changed]).distinctFailedCodeAttempts == 0)
    }

    @Test func legacyJSONDecodesWithoutChangingHistoricalRecords() throws {
        let legacy = attempt("SELECT 1", kind: nil)
        let encoded = try JSONEncoder().encode(legacy)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["submissionKind"] == nil)
        let decoded = try JSONDecoder().decode(Attempt.self, from: encoded)
        #expect(decoded.id == legacy.id && decoded.sql == legacy.sql && decoded.submissionKind == nil)
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: [decoded]).distinctFailedCodeAttempts == 0)
        let classified = attempt("SELECT 2")
        let restored = try JSONDecoder().decode(Attempt.self, from: JSONEncoder().encode(classified))
        #expect(restored.submissionKind == .gradedCode && restored.id == classified.id)
    }

    @Test func distinctFailuresAndCategoriesSurviveConnectionCloseAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-SolutionAccess-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("progress.sqlite")
        do {
            let store = try ProgressStore(url: url)
            for index in 1...9 { try store.record(attempt("SELECT \(index)")) }
            try store.record(attempt("SELECT 90", kind: .infrastructureFailure))
            try store.record(attempt("SELECT 91", passed: true))
        }
        do {
            let reopened = try ProgressStore(url: url)
            let nine = SolutionAccessPolicy(exerciseID: "target", attempts: try reopened.attempts())
            #expect(nine.distinctFailedCodeAttempts == 9 && !nine.isUnlocked)
            try reopened.record(attempt("SELECT 10"))
        }
        let reopened = try ProgressStore(url: url)
        let history = try reopened.attempts()
        #expect(history.filter { $0.submissionKind == .infrastructureFailure }.count == 1)
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: history).isUnlocked)
        #expect(SolutionAccessPolicy(exerciseID: "target", attempts: history).distinctFailedCodeAttempts == 10)
    }

    @Test func backupMergePreservesUnlockWithoutCountingOverlapOrNewFormatting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SQLLY-SolutionImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("progress.sqlite")
        let initial = (1...9).map { attempt("SELECT \($0)") }
        do {
            let store = try ProgressStore(url: url)
            for entry in initial { try store.record(entry) }
            let overlap = Array(initial.prefix(5))
            let formatting = (1...5).map { attempt(" select \($0); -- imported formatting") }
            let excluded = [attempt("SELECT 90", kind: .infrastructureFailure), attempt("SELECT 91", kind: .assessment),
                            attempt("SELECT 92", kind: nil), attempt("SELECT 93", passed: true)]
            let incoming = overlap + formatting + [attempt("SELECT 10")] + excluded
            let backup = ProgressBackup(formatVersion: 1, exportedAt: Date(), progress: [:], attempts: incoming, drafts: [:], position: nil)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)
            try store.importData(data); try store.importData(data)
            #expect(try store.attempts().count == 19)
            let exported = try store.exportData()
            let second = try ProgressStore(url: root.appendingPathComponent("second.sqlite"))
            try second.importData(exported)
            let imported = SolutionAccessPolicy(exerciseID: "target", attempts: try second.attempts())
            #expect(imported.distinctFailedCodeAttempts == 10 && imported.isUnlocked)
        }
        let reopened = try ProgressStore(url: url)
        let policy = SolutionAccessPolicy(exerciseID: "target", attempts: try reopened.attempts())
        #expect(policy.distinctFailedCodeAttempts == 10 && policy.isUnlocked)
    }
}
