# Historical verification: SQLLY 0.3.0

SQLLY 0.3.0/build 3 was built and inspected on Apple Silicon/macOS 27.2 with Swift 6.4 and the macOS 27 SDK. The full automated suite, final optimized app, and mounted disk image passed the checks below. Source-archive verification is recorded at the end. Completed checks and retained baseline evidence are separated below.

## Preserved evidence

SQLLY 0.2.0 passed 41 tests in 10 suites in 386.292 seconds before two subsequent UI-only localization fixes, which were built and manually inspected. Its 516 installed answers included 510 SQL tasks and produced 1,020 fixture comparisons. Its optimized app and read-only DMG launched and executed real PostgreSQL queries on Apple Silicon/macOS 27.2. See [the archived 0.2.0 report](SQLLY-0.2.0.md) and [the original 0.1.0 report](QueryCraft-0.1.0.md). Those checks establish a baseline; they do not verify the new Learning Center, activity history, controls, or layout.

## Prepared release work

- Preserved the previous DMG, source ZIP, checksums, checklist, and machine-readable reports before replacing current deliverables.
- Updated build defaults to app version 0.3.0 and build 3. The executable, app, and DMG volume remain SQLLY.
- Kept the established bundle identifier `org.querycraft.QueryCraft` and data directory `~/Library/Application Support/QueryCraft` for update compatibility.
- Retained the original AppKit vector icon, bundled PostgreSQL 18.6 runtime, MIT project license, and upstream dependency notices.
- A read-only audit of the retained runtime passed: 39 arm64 native files with only macOS-system or bundle-relative dependencies, 697 regular runtime files scanned with no developer-home paths, zero external Swift packages, and existing MIT/upstream notices present. This audits the retained runtime, not a new app build.
- Bash syntax checks passed for app, DMG, and source packaging scripts. The optimized build uses a separate Swift scratch directory.

## Activity tests executed

The isolated activity build succeeded, and all 12 `LearningActivityTests` passed in 0.012 seconds. They cover local midnight, spring/fall daylight-saving transitions, leap day, the 182-day display boundary, repeated and failed submissions, first lifetime success, UUID deduplication/conflicts, future timestamps, lifetime streaks, and yesterday grace. The integrated full suite subsequently passed as recorded below.

## Integrated automated tests

The full suite passed **53 tests in 11 suites in 372.929 seconds**. Every installed answer was checked: **516 answers**, including **510 SQL answers**, **2 predictions**, and **4 conceptual responses**; SQL grading produced **1,020 fixture comparisons**. The report counted 512 reference previews, while expected-result examples were verified for the 102 lessons. Activity tests augment the existing execution, result comparison, grading, safety, persistence, and localization coverage.

Subsequent changes are limited to UI rendering and localization: heatmap month-label alignment, language-explicit formatted date strings, a shorter Russian back label, clipped editor-ruler painting, light/dark selected-step contrast, compact scrollable Settings, and visible backup success notices. Core execution, grading, fixtures, curriculum SQL, and activity aggregation remain unchanged. The final optimized build and native checks subsequently passed; this is not a claim that the full suite was rerun afterward.

## Native interface checks

A manual Russian/light-appearance QA run confirmed larger controls, a readable Continue arrow, and removal of the requested editor metadata/status footer. Completing an introduction updated its topic rail to 1/21; a subsequent incorrect submission and correct submission produced 2/21 completed learning steps. The daily calendar showed two submissions, one correct answer, one first solve, and a one-day streak. Selecting the calendar day opened its submission history, the course map found the current lesson, and the Learning Center Settings export produced a real local backup file. The native import chooser then selected that same JSON backup successfully; merge preserved the two existing attempt IDs without duplication. Switching Russian → English inside the Learning Center Settings retained the section and updated native menus; dark Settings were also inspected.

Subsequent native checks confirmed the editor ruler no longer crosses its header, selected-step contrast is readable in light appearance, month labels run May–October without overlap, and dark calendar/map/reading rails remain clear. Restart retained both test submissions and their one active day, current streak, and first solve. Language-explicit DateFormatter strings were then confirmed in the optimized app: Russian day/date and submission timestamps displayed in Russian regardless of the operating-system language. The local merge success notice was visible in Russian. Command-Shift-L opened the Learning Center, and choosing Keys & Relationships on the map dismissed the center and opened numbered lesson step 8. They are manual interface observations rather than an automated XCUITest suite. This pass inspected the current application window and the 960×680 Learning Center; panel dragging and minimum-window sizing were not separately tested. Earlier native zoom/collapse evidence remains in the archived baseline.

## Optimized app assembly

The version 0.3.0/build 3 release assembled successfully with the separate Swift scratch directory. Plist and strict deep signature validation passed. Both English and Russian interfaces contain 311 matching keys with matching format placeholders. The bundled course remains version 1.1.0 with 34 topics, 102 lessons, and 516 tasks. The app contains 138 state checks and seven immediate-output contracts.

The arm64 app retains the original 148,065-byte icon. Its 715 file entries passed the developer-home-path byte scan. All 39 PostgreSQL Mach-O files passed architecture and dependency validation. No new native library or Swift package dependency was introduced. See [the app audit](SQLLY-0.3.0-release-audit.json).

## Disk image and relocated execution

`SQLLY-0.3.0-arm64.dmg` passed image-integrity and SHA-256 checks. It mounted read-only at `/Volumes/SQLLY 1`, preserving the user's already mounted 0.2.0 volume at `/Volumes/SQLLY`. Version metadata confirmed the new mounted app was 0.3.0/build 3 before its audit. The image contains SQLLY.app, bilingual installation notes, and the conventional `Applications` symlink. The mounted app passed strict deep signing, exact resource parity, the 715-file privacy scan, and the 39-native runtime audit.

The relocated PostgreSQL 18.6 runtime initialized a new cluster and authenticated through SCRAM on a private Unix socket. A real recursive CTE and JSONB query returned `6|object`; the temporary server and cluster were cleaned up. The integration owner then confirmed that both the native application and its PostgreSQL server executable ran from `/Volumes/SQLLY 1/SQLLY.app`. Automatic execution and Command-Return returned six real customer names. Command-Shift-L and the sidebar opened the new Learning Center, where the preserved history correctly showed zero submissions and a zero-day streak, a Russian date heading, and an accurate first-submission empty state. The app quit, only the newly mounted image detached, and the user's existing volume remained mounted. See [the package audit](SQLLY-0.3.0-package-audit.json).

## Source archive

`SQLLY-source.zip` contains **88 source, content, documentation, test, and license files** across **110 ZIP entries**. ZIP CRC and privacy checks passed. The archive includes the new Learning Center, activity calculation/tests, current bilingual 516-task packs, and final verification evidence. It excludes build caches, generated PostgreSQL binaries, app/DMG outputs, progress backups and databases, signing material, and developer-home identifiers. The archive was regenerated after this report and checklist were finalized, then checked again with `unzip -t`, Python ZIP verification, and both basename-only SHA-256 sidecars. See [the source audit](SQLLY-0.3.0-source-audit.json).

## User-data preservation

After native QA, the integration owner independently compared the persisted progress, drafts, settings, and attempt row values with the pre-test baseline. All matched, and original language, appearance, and editor-size preferences were retained. No test activity or personal progress backup is included in the source release.

## Release limits

The release remains a local development build with ad-hoc signatures unless a real Developer ID identity is supplied. No notarization credentials are invented. Intel, execution on the macOS 14 deployment target, independent accessibility/security review, and separate clean-machine validation remain release work. The GitHub workflow has not been run remotely in this session.
