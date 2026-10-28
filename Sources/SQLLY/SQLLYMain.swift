import Foundation
import SwiftUI
import Darwin

/// Keep release verification ahead of SwiftUI and WorkspaceModel creation.
/// This permits a relocated .app to check its own resources without opening a
/// window or reading and migrating the learner's progress database.
@main @MainActor enum SQLLYMain {
    static func main() async {
        if CommandLine.arguments.contains("--verify-bundled-resources") {
            do {
                let summary = try await BundledResourcesVerifier.run()
                FileHandle.standardOutput.write(Data((summary + "\n").utf8))
                exit(EXIT_SUCCESS)
            } catch {
                let diagnostic = "SQLLY bundled-resource verification failed: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(diagnostic.utf8))
                exit(EXIT_FAILURE)
            }
        }
        SQLLYApp.main()
    }
}
