# Historical verification: SQLLY 0.2.0

This record describes checks actually run on 28 October 2026. The SQLLY app was built on Apple Silicon with Swift 6.4 and the macOS 27 SDK, and inspected on macOS 27.2. Final disk-image checks are recorded separately below.

## Preserved baseline

The existing QueryCraft 0.1.0 implementation passed 26 automated tests in six suites in 233.124 seconds, including 306 SQL answers across 612 fixture comparisons, 102 PostgreSQL-generated lesson previews, persistence, grading, isolation, privilege restrictions, timeout enforcement, and recovery. Its app and DMG launched on Apple Silicon/macOS 27.2. That evidence is retained in [the historical verification report](QueryCraft-0.1.0.md); it does not by itself verify SQLLY's new controls, navigation, localization, or live execution.

## SQLLY changes

- Inspected the existing implementation and the user's modification requirements.
- Kept the existing PostgreSQL 18.6 binaries and original SQL fixtures/reference solutions; no database runtime rebuild was needed for the rename.
- Updated app assembly, disk-image/source packaging, visible product names, metadata, and default version to SQLLY 0.2.0.
- Kept `org.querycraft.QueryCraft` and `~/Library/Application Support/QueryCraft` intentionally, preserving existing settings and learning data across the rename.
- Inspected the requested Bootstrap Database reference and its MIT license. The new icon uses original AppKit vector paths, not copied SVG/font geometry.
- Executed the icon generator, created a valid ICNS, and inspected its rendered black/white cylinder with green accent.
- Bash syntax checks passed for modified app/DMG/source packaging scripts.

## Automated tests and course audit

The full `swift test` run passed **41 tests in 10 suites in 386.292 seconds**. This completed run supersedes an earlier timing-dependent test failure observed during parallel database work; the live-controller test now uses a controlled continuation rather than assuming a running query starts within a fixed sleep. Two subsequent UI-only localization fixes (the worked-solution label and an untouched exploration-comment language switch) were verified by an optimized build and manual interface checks; the full suite was not rerun after those UI changes. Core execution, grading, fixtures, and curriculum SQL were unchanged.

Coverage includes result comparison (NULLs, duplicates, ordering, exact numeric precision, and JSONB numeric values), alternative valid queries, fixture reset after errors or destructive statements, concurrent isolation, role and filesystem restrictions, hard timeouts, result/statement limits, abandoned-cluster recovery, interrupted transactions, progress persistence, export/import, and atomic migration of the former reading-step layout. Live tests verify debounce/coalescing, suppression of superseded results, actual PostgreSQL timeout recovery, context-specific fixtures, cancellation, and terminal shutdown without restarting a delayed database request.

Every installed answer was checked: **516 answers**, comprising **510 SQL tasks, 2 prediction tasks, and 4 conceptual response tasks**. SQL grading produced **1,020 fixture comparisons**. The run generated expected-result previews for all **102 lessons**; its broader reference report counted 512 previews, which is not a lesson count. Mutation tests additionally reject incorrect or omitted RETURNING output, fake sequences, and hidden destructive changes while accepting equivalent valid submissions without executing a mutation twice.

The English and Russian course packs are both version **1.1.0** and contain **34 topics, 102 lessons, and 516 exercises**. Each concept offers five practice tasks, or six where a conceptual response task is included. The translation audit found 1,122 translated lesson sections, 516 translated prompts, and 1,548 translated hints with no missing translations. Fixtures, reference/check SQL, stable identifiers, and grading policies match between languages; localized starter instruction comments are permitted. See [the content audit](localization-content-audit.json).

## App assembly and binary audit

The optimized release assembly completed using a separate Swift scratch directory. `codesign --verify --deep --strict` and plist validation passed. Both resource bundles contain the current English/Russian course and interface resources. The arm64 app uses the original 148,065-byte ICNS. A byte scan of all **715 app file entries** found zero developer-home path strings. All **39 PostgreSQL Mach-O files** passed architecture and dependency inspection: dependencies resolve inside the bundle or to macOS system libraries. See [the release audit](SQLLY-0.2.0-release-audit.json).

## Native interface observations

The integration owner inspected the running native debug build in both light and dark appearances. The flat Russian topic sidebar, numbered steps, readable lesson/editor/results, and black/charcoal/green dark design were visible. Switching Russian → English → Russian refreshed all 34 topic titles, course prose, Settings, and native application menu titles while retaining the SQL draft and learning progress.

Typing an invalid `SELEC` statement produced localized Russian syntax guidance automatically. Replacing it with an alternative valid `SELECT c.* ... ORDER BY c.id` recovered six rows after the typing pause, without pressing Run or awarding completion. Explicit Shift-Command-Return submission of an incorrect answer marked it for review; ordinary live execution left completion at 1/516. These observations complement the automated stale-result and debounce tests; they are manual checks rather than an automated XCUITest suite.

The final optimized app also launched with clean progress at 0/516 and PostgreSQL 18.6 ready. The Russian introduction, schema browser, and sample data executed successfully. The untouched exploration comment switched correctly in both directions between English and Russian; learner-authored SQL remained intact. The Russian worked-solution disclosure expanded on request to show reference SQL and its Russian explanation. Correct/incorrect grading, progressive hints, history, and quit/restart persistence were exercised in the optimized build. Its final dark appearance was inspected again.

## Disk image

`scripts/package-dmg.sh` produced `SQLLY-0.2.0-arm64.dmg` and its basename-only SHA-256 sidecar. Image integrity and checksum verification passed. The image mounted read-only at `/Volumes/SQLLY` with SQLLY.app, an `Applications` symlink targeting `/Applications`, and bilingual installation notes. The mounted app passed strict deep signature validation and the complete 715-file content/privacy audit. Its 39 native PostgreSQL files passed dependency/architecture inspection.

The mounted runtime initialized a fresh cluster, authenticated through SCRAM on a private Unix socket, and executed a recursive CTE combined with JSONB type inspection. Its real result was `6|object`. The temporary server and cluster were cleaned up. This verifies resource relocation independently of the native interface.

The integration owner launched the mounted native app and confirmed that both its executable and PostgreSQL server process came from `/Volumes/SQLLY/SQLLY.app`. An alternative customer query automatically returned six rows while completion stayed at 0/516. Explicit Shift-Command-Return submission passed both grading fixtures and increased completion to one. Searching for Window filtered the sidebar; opening Window Function Foundations showed 22 numbered steps, and a real `SUM(...) OVER (...)` query returned six rows automatically. The app quit and the volume detached successfully. See [the package audit](SQLLY-0.2.0-package-audit.json).

## Source archive

`SQLLY-source.zip` contains **80 source, documentation, content, and license files** across **102 ZIP entries**. Both `unzip -t` and Python ZIP CRC verification passed. Inspection confirmed the native Swift sources, current bilingual 516-task packs, extra practice authoring files, scripts, and license material are present. Build caches, generated PostgreSQL binaries, app/DMG outputs, signing material, user progress, and developer-home identifiers are excluded. The pinned build script recreates the native database runtime from official source. The archive was regenerated after this verification record and checklist were finalized, then checked again. Both basename-only SHA-256 sidecars verified successfully. See [the source audit](SQLLY-0.2.0-source-audit.json).

## Release limits

The release remains a local development build with ad-hoc signatures unless a real Developer ID identity is supplied. No notarization credentials are invented. Intel, execution on the macOS 14 deployment target, independent accessibility/security review, and separate clean-machine validation remain release work. The GitHub workflow has not been run remotely in this session.
