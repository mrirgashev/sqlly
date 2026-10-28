import Foundation
import SQLCore

/// A release smoke test of the same resource APIs used by the application.
/// It intentionally supplies no runtime URL, so source/build-directory fallbacks
/// cannot conceal a broken PostgreSQL location inside the packaged application.
@MainActor enum BundledResourcesVerifier {
    static func run() async throws -> String {
        let fm = FileManager.default
        let application = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        try require(application.pathExtension.lowercased() == "app", "Run the executable inside SQLLY.app, not a SwiftPM build product.")
        guard let core = SQLLYResources.coreBundle else { throw VerificationError("The app's SQLCore resource bundle is missing.") }
        guard let interface = SQLLYResources.interfaceBundle else { throw VerificationError("The app's interface resource bundle is missing.") }
        try verifyContainment(of: core, in: application, name: "SQLCore")
        try verifyContainment(of: interface, in: application, name: "interface")

        let english = try Curriculum.load(language: .english)
        let russian = try Curriculum.load(language: .russian)
        try require(!english.lessons.isEmpty && !english.exercises.isEmpty, "The English curriculum has no lessons or exercises.")
        try require(english.lessons.map(\.id) == russian.lessons.map(\.id)
                    && english.exercises.map(\.id) == russian.exercises.map(\.id), "The English and Russian curriculum identifiers differ.")
        try require(english.title != russian.title, "The Russian curriculum resolved to English content.")
        try require(CoreText.text("Row order was checked.", language: .russian) == "Порядок строк проверен.", "Russian SQLCore strings did not load.")
        try require(L.text("Completed", language: "ru") == "Выполнено", "Russian interface strings did not load.")

        let temporary = fm.temporaryDirectory.appendingPathComponent("SQLLY-resource-verification-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let engine = PostgresEngine(baseURL: temporary)
        do {
            let fixture = """
            CREATE TABLE verification_values(id integer PRIMARY KEY, amount numeric(10,2));
            INSERT INTO verification_values VALUES (1,1.25),(2,NULL),(3,1.25);
            """
            let result = try await engine.execute(sql: """
            SELECT current_user::text AS practice_role, amount, amount IS NULL AS is_missing
            FROM verification_values ORDER BY id;
            """, fixture: fixture)
            let expected: [[String?]] = [["learner", "1.25", "f"], ["learner", nil, "t"], ["learner", "1.25", "f"]]
            try require(result.columns.map(\.name) == ["practice_role", "amount", "is_missing"] && result.rows == expected,
                        "The bundled PostgreSQL query returned unexpected role, values, NULLs, duplicate rows, or column names.")
        } catch {
            await engine.shutdown()
            try? fm.removeItem(at: temporary)
            throw error
        }
        await engine.shutdown()
        try fm.removeItem(at: temporary)
        return "SQLLY bundled resources verified: app-contained bundles, English/Russian curricula (\(english.exercises.count) exercises), both Russian string tables, PostgreSQL learner query with NULL and duplicate rows."
    }

    private static func verifyContainment(of bundle: Bundle, in application: URL, name: String) throws {
        try requireContained(bundle.bundleURL, in: application, description: "\(name) bundle")
        guard let resources = bundle.resourceURL else { throw VerificationError("The \(name) bundle has no resource URL.") }
        try requireContained(resources, in: application, description: "\(name) resource directory")
        guard let items = FileManager.default.enumerator(at: bundle.bundleURL, includingPropertiesForKeys: nil) else {
            throw VerificationError("Cannot enumerate the \(name) resource bundle.")
        }
        for case let item as URL in items {
            try requireContained(item, in: application, description: "\(name) resource \(item.lastPathComponent)")
        }
    }

    private static func requireContained(_ url: URL, in application: URL, description: String) throws {
        let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let root = application.pathComponents
        try require(url.isFileURL && components.count > root.count && Array(components.prefix(root.count)) == root,
                    "The \(description) resolves outside the application: \(url.path)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw VerificationError(message) }
    }

    private struct VerificationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
