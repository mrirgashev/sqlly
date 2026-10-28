# SQLLY 0.3.2 build verification

Version 0.3.2/build 5 fixes resource lookup in SwiftPM tests and in the installed macOS application. The bundle identifier and learning-data location remain unchanged. Earlier installer and application evidence is preserved in [0.3.1](verification/SQLLY-0.3.1.md) and [0.3.0](verification/SQLLY-0.3.0.md).

## Reproduced failure and correction

[The initial GitHub run](https://github.com/mrirgashev/sqlly/actions/runs/40723306054) built PostgreSQL and compiled Swift successfully, then failed its tests with a missing bundled-runtime error. A clean local checkout using `swift test --build-system native` reproduced that error in `realPostgresTypesNullsDuplicatesUnicode`.

The native SwiftPM builder places copied content at `SQLLY_SQLCore.bundle/Resources/Postgres`. Swift Build uses `SQLLY_SQLCore.bundle/Contents/Resources/Resources/Postgres`. Appending `Resources/Postgres` unconditionally to Foundation's resource URL failed for the native layout. Separately, the native generated `Bundle.module` accessor could fall back to the original absolute build directory when app assembly moved its bundles into `Contents/Resources`.

`SQLLYResources` now locates the app's own named resource bundles and discovers a complete PostgreSQL runtime in either layout. CLI/tests locate their adjacent resource bundles. Installed `.app` bundles, including uppercase extensions, never search owner/parent build directories. All curriculum, engine, and localization callers use this resolver. Missing or incomplete runtimes fail before initialization of engine data; explicit runtime overrides cannot silently select another server.

## Local execution

- Full native SwiftPM suite: **57 tests in 12 suites passed in 372.091 seconds**, including all 516 reference answers, 1,020 fixture comparisons, 512 previews, grading alternatives, timeouts, isolation, persistence, and localization. A final case-insensitive app-extension adjustment is additionally covered by the focused checks below.
- Final-source focused checks with the default Swift Build engine: **5 tests in 2 suites passed in 1.396 seconds**, including both resource layouts, lower/uppercase app containment, missing-runtime behavior, both curricula, and a real PostgreSQL query.
- The same final-source focused checks also passed with the native SwiftPM builder.
- Optimized native SwiftPM app assembly: passed as **0.3.2/build 5, arm64**; strict deep code-signature and metadata checks passed.
- A copy outside the checkout passed `--verify-bundled-resources` while its original release build cache was renamed away. Both 516-exercise curricula, both Russian string tables, app-contained resources, and a real learner query with NULL, numeric precision, duplicate rows, and required ordering passed. The temporary engine shut down and its state was removed; the build cache was restored.
- Normal native launch of that relocated copy succeeded. Command-Return returned **6 rows** in the editor's results table. No answer submission was made during this UI check.
- All **715 app files** passed the developer-home/build-path scan.
- Updated DMG creation, `hdiutil verify`, and SHA-256 sidecar verification passed. A private read-only mount passed the two-icon Finder layout check, Applications symlink, strict signature, bilingual resource parity, 715-file privacy scan, 39-file arm64 runtime audit, and the mounted app's real-query diagnostic. The audit mount was detached.
- Shell syntax, workflow YAML, every workflow shell block, and cache-restoration success/failure checks passed.

The diagnostic branches before creating the SwiftUI app or `WorkspaceModel`. It uses a fresh temporary PostgreSQL data directory and does not open the learner's progress database. CI runs this same diagnostic after temporarily moving `.build` away and restores the cache with an exit trap before DMG packaging.

## Remote CI

The [GitHub Actions workflow](https://github.com/mrirgashev/sqlly/actions/workflows/ci.yml) records the remote result for each commit. Local evidence above does not establish a remote outcome; inspect the corresponding run's test, package, diagnostic, and artifact steps.

## Release limits

This remains an Apple Silicon development package with ad-hoc signatures. No Developer ID signing, notarization, Intel execution, or independent macOS 14 validation is claimed. The remaining public-release work in [CHECKLIST.md](CHECKLIST.md) still applies.
