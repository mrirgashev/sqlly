import Foundation
import Testing
@testable import SQLCore

struct ResourceBundleTests {
    @Test(arguments: [false, true])
    func runtimeSupportsBothSwiftPMResourceLayouts(nested: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("SQLLY_SQLCore.bundle")
        let resourceRoot = nested ? url.appendingPathComponent("Contents/Resources") : url
        try FileManager.default.createDirectory(at: resourceRoot, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.sqlly.test.\(UUID().uuidString)"], format: .xml, options: 0)
        try info.write(to: nested ? url.appendingPathComponent("Contents/Info.plist") : url.appendingPathComponent("Info.plist"))
        let runtime = resourceRoot.appendingPathComponent("Resources/Postgres")
        try makeRuntimeDirectory(runtime)
        let bundle = try #require(Bundle(url: url))
        #expect(SQLLYResources.postgresRuntime(in: bundle)?.standardizedFileURL == runtime.standardizedFileURL)
        try FileManager.default.removeItem(at: runtime.appendingPathComponent("bin/initdb"))
        #expect(SQLLYResources.postgresRuntime(in: bundle) == nil)
    }

    @Test(arguments: ["app", "APP"])
    func installedAppUsesItsOwnBundlesWithoutBuildFallback(extension appExtension: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("SQLLY.\(appExtension)")
        let app = try makeBundle(at: appURL, contents: true, packageType: "APPL")
        let decoy = try makeBundle(at: root.appendingPathComponent("Build/Tests.xctest"), contents: true)
        _ = try makeBundle(at: root.appendingPathComponent("Build/SQLLY_SQLCore.bundle"))
        #expect(SQLLYResources.findBundle(named: "SQLLY_SQLCore", main: app, owner: decoy) == nil)
        let bundledURL = appURL.appendingPathComponent("Contents/Resources/SQLLY_SQLCore.bundle")
        _ = try makeBundle(at: bundledURL)
        #expect(SQLLYResources.findBundle(named: "SQLLY_SQLCore", main: app, owner: decoy)?.bundleURL.path == bundledURL.path)
        #expect(SQLLYResources.findBundle(named: "SQLLY_SQLCore", main: decoy, owner: decoy)?.bundleURL.path == root.appendingPathComponent("Build/SQLLY_SQLCore.bundle").path)
    }

    @Test func testRunnerFindsShippedCurriculaAndCompleteRuntime() throws {
        let core = try #require(SQLLYResources.coreBundle)
        #expect(SQLLYResources.postgresRuntime(in: core) != nil)
        let english = try Curriculum.load()
        let russian = try Curriculum.load(language: .russian)
        #expect(!english.exercises.isEmpty)
        #expect(english.exercises.map(\.id) == russian.exercises.map(\.id))
        #expect(CoreText.text("Row order was checked.", language: .russian) == "Порядок строк проверен.")
    }

    @Test func explicitMissingRuntimeDoesNotFallBackToBundledServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = PostgresEngine(baseURL: root.appendingPathComponent("state"), runtimeURL: root.appendingPathComponent("missing"))
        do {
            try await engine.start()
            Issue.record("A missing explicitly selected runtime must fail")
        } catch let error as PostgresError {
            #expect(error.message.contains("runtime is missing"))
        }
        await engine.stop()
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("state").path))
    }

    private func makeBundle(at url: URL, contents: Bool = false, packageType: String = "BNDL") throws -> Bundle {
        let directory = contents ? url.appendingPathComponent("Contents/Resources") : url
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.sqlly.test.\(UUID().uuidString)", "CFBundlePackageType": packageType], format: .xml, options: 0)
        try plist.write(to: contents ? url.appendingPathComponent("Contents/Info.plist") : url.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: url))
    }

    /// These empty files only test directory discovery. Actual SQL execution is
    /// covered by PostgresEngineTests and the packaged executable smoke check.
    private func makeRuntimeDirectory(_ url: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: url.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try files.createDirectory(at: url.appendingPathComponent("lib"), withIntermediateDirectories: true)
        for name in ["bin/postgres", "bin/initdb", "lib/libpq.5.dylib"] {
            let file = url.appendingPathComponent(name)
            try Data().write(to: file)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
    }
}
