import Foundation

/// Resolves the resources shipped with this executable, without SwiftPM's
/// generated absolute build-directory fallback. Both SwiftPM build systems and
/// the assembled macOS app use the same bundle names but different layouts.
public enum SQLLYResources {
    public static let coreBundle = findBundle(named: "SQLLY_SQLCore", main: .main, owner: Bundle(for: ResourceOwner.self))
    public static let interfaceBundle = findBundle(named: "SQLLY_SQLLY", main: .main, owner: Bundle(for: ResourceOwner.self))

    static func findBundle(named name: String, main: Bundle, owner: Bundle) -> Bundle? {
        var roots = [main.resourceURL, main.bundleURL]
        // An installed application must be self-contained. Tests and `swift run`
        // instead place resource bundles beside the test bundle or executable.
        if main.bundleURL.pathExtension.lowercased() != "app" {
            roots += [owner.resourceURL, owner.bundleURL,
                      main.bundleURL.deletingLastPathComponent(), owner.bundleURL.deletingLastPathComponent()]
        }
        for root in roots.compactMap({ $0 }) {
            if let bundle = Bundle(url: root.appendingPathComponent("\(name).bundle", isDirectory: true)) {
                return bundle
            }
        }
        return nil
    }

    static func postgresRuntime(in bundle: Bundle?) -> URL? {
        guard let bundle else { return nil }
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Resources/Postgres", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("Postgres", isDirectory: true),
            bundle.bundleURL.appendingPathComponent("Resources/Postgres", isDirectory: true)
        ]
        return candidates.compactMap { $0 }.first(where: isCompleteRuntime)
    }

    static func isCompleteRuntime(_ directory: URL) -> Bool {
        let files = FileManager.default
        return files.isExecutableFile(atPath: directory.appendingPathComponent("bin/postgres").path)
            && files.isExecutableFile(atPath: directory.appendingPathComponent("bin/initdb").path)
            && files.fileExists(atPath: directory.appendingPathComponent("lib/libpq.5.dylib").path)
    }
}

private final class ResourceOwner: NSObject {}
