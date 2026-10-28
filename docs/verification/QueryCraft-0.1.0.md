# Historical verification: QueryCraft 0.1.0

This is retained evidence for the pre-SQLLY release. It does not establish verification of later modifications.

# Verification record

Verification performed on 28 October 2026. Executed checks and remaining release validation are recorded below.

Environment inspected: Apple Silicon (`arm64`), macOS host toolchain reporting macOS 27.2, Xcode selected at `/Applications/Xcode.app/Contents/Developer`, Swift 6.4. `hdiutil` and Xcode command-line tools are available.

Research completed: official PostgreSQL architecture sources, local skill inventory, both requested upstream design instructions, public Stepik hierarchy and SQL task metadata, and official Stepik support/course pages. No live learner submission was made on Stepik.

Completed binary audit: all 39 retained PostgreSQL executables/libraries inspected with `file`, `otool -L`, and `vtool -show-build`; every binary is arm64, every LC_BUILD_VERSION minimum is macOS 14.0, and no dependency points to Homebrew or a developer build directory. Linked libraries are bundled relative paths or `/usr/lib/libSystem.B.dylib`. Every relative dependency was resolved to an existing file inside the runtime. The final runtime was rebuilt using a stable virtual installation prefix and compiler path mapping; a byte scan of all 701 runtime file entries found zero `/Users/` developer-home paths. See [machine-readable runtime audit](runtime-binary-audit.json). This establishes the declared minimum build target, not execution on macOS 14.

License audit retained the main PostgreSQL COPYRIGHT plus 75 distinct upstream notice blocks, Tcl regex, Snowball, Unicode V3, Boost/Ryu, and timezone notices in `licenses/` and the bundled runtime. No optional external dylibs were found.

Original vector icon generation was executed successfully; `file` recognized the output as an ICNS file. Bash syntax checks passed for app/DMG/source packaging scripts.

## Automated checks executed

The complete `swift test` run passed **26 tests in 6 suites in 233.124 seconds**. The run included:

- 10 PostgreSQL integration tests: real NULLs/duplicates/types/Unicode, final-statement scripts, committed DML/schema validation, destructive reset, privilege denials, deadline bypass attempts, output limits, advanced PostgreSQL features, concurrent submission isolation, transaction/role poisoning recovery, and abandoned-cluster recovery.
- Result comparison checks for row ordering, duplicate multiplicity, NULL/empty/text distinctions, exact arbitrary numeric precision, output columns, and unambiguous cell boundaries.
- SQLite close/reopen persistence, atomic backup merge, malformed/future backup rejection, damaged-file preservation, and local-history preservation on UUID conflicts.
- Curriculum integrity and dedicated constraint/state validation, alternative correct-query acceptance, rejection of hardcoded result answers, and prediction/choice assessment including invalid submissions.
- **All 306 SQL reference answers on two fixtures each: 612 fixture comparisons**, plus two prediction references and four conceptual-task metadata checks, across the installed 312 exercises.
- Actual PostgreSQL-generated expected-result previews for **all 102 lessons**.

These checks used the real bundled PostgreSQL 18.6 engine. No SQL evaluator or query-string comparison was substituted. The source runtime relocation smoke also passed: initialization, private socket/SCRAM authentication, recursive CTE, JSONB, and expected output `6|object`.

## Native UI inspection

The integration owner ran the optimized release app and verified an alternative correct SQL answer against both fixtures, incorrect-answer feedback, SQL highlighting, line numbers, schema browsing, progressive hints, bookmarks, review flags, attempt history, progress export, and light/dark appearance. The final 312-task UI was searched by exercise ID. Native prediction-grid submission, exact multi-choice assessment (correct and incorrect sets), and written explanation/rubric self-assessment were exercised with the SQL workspace collapsed. Workspace collapse and native window zoom changed the layout successfully; direct split-divider dragging was not separately confirmed. Keyboard checks passed for ⌘Return (Run), ⇧⌘Return (Submit), ⇧⌘B (Bookmark), and ⇧⌘E (Export). The native Save panel produced a valid JSON backup with the observed attempt/progress records. After quitting, no QueryCraft engine processes remained; reopening restored completion, review/bookmark flags, draft SQL, current exercise, and attempt history. Import behavior was exercised by automated core tests; the native Open panel and merge explanation opened, but successful file selection/import was not separately confirmed. These are manual observations, not an automated XCUITest suite.

## Packaged release checks

`CONFIGURATION=release CODE_SIGN_IDENTITY=- ./scripts/build-app.sh` completed successfully. The release executable has linker debug symbols stripped before final signing, removing developer-home paths. The app contains the complete 312-task course and all runtime license notices. Whole-app inspection found zero `/Users/` strings across 709 file entries, no stale flat PostgreSQL module copies, and no PGXS developer makefiles. `codesign --verify --deep --strict` passed.

`./scripts/package-dmg.sh` produced `QueryCraft-0.1.0-arm64.dmg` and a basename-only SHA-256 file. `hdiutil verify` passed, and the image mounted read-only at `/Volumes/QueryCraft`. It contains the app, installation notes, and the conventional `Applications` symlink. The mounted app's signature passed strict deep verification. Its 39 PostgreSQL Mach-O files passed architecture and dependency checks; the entire mounted app passed the developer-home-path byte scan.

The **mounted DMG's own runtime** initialized a new cluster, authenticated through SCRAM on a private socket, and executed a recursive CTE plus JSONB query with the expected `6|object` result. This tests relocation of the shipped runtime, independently of the build-directory copies.

The mounted app then launched through native UI automation. Process executable paths confirmed that both the app and PostgreSQL server ran from the mounted volume. Clean first launch showed 0/312 exercises complete and all 34 modules/102 lessons. ⌘Return executed the real query returning `Hello, PostgreSQL!` (one row), with PostgreSQL 18.6 local status. The final three-panel workspace, readable lesson/editor, and results were visually inspected.

The app quit cleanly after this check, and the disk image detached successfully. The development image is ad-hoc signed; no Developer ID signing or notarization was performed.

## Source archive

`QueryCraft-source.zip` contains 55 source/document/license files (72 total entries). `unzip -t` and Python's ZIP CRC check passed. Inspection confirmed the installed 34-module/102-lesson/312-exercise JSON is included. The archive excludes build caches, app/DMG outputs, generated native PostgreSQL binaries, tester progress, credentials/signing material, and developer-home identifiers. The pinned PostgreSQL build script regenerates the runtime from official source. A basename-only SHA-256 sidecar accompanies the archive.

## Remaining validation

Successful native file-selection/import remains unconfirmed; its core merge behavior passed automated tests. Direct split-divider dragging was not separately confirmed. Intel, execution on the macOS 14 deployment target, public notarization, independent accessibility/security review, and separate clean-machine release testing remain release work. The included GitHub workflow has not been executed remotely.
