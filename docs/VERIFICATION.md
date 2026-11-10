# SQLLY 0.3.6 verification

Version 0.3.6/build 9 adds Command-Return submission, focus transfer after accepted answers, success outlines on the original step icons, automatic reading completion and the Result/Data workspace. New tasks with existing fixture tables start with SELECT from the relevant table. Saved drafts, including intentionally empty drafts, are restored verbatim. Custom repair/completion starter SQL is also displayed in the task instructions. The course packs, reference answers and grading policies retain their existing definitions.

## Automated checks

The full native SwiftPM run passed **104 tests in 20 suites in 365.534 seconds**. It checked 516 reference answers, 1,020 SQL fixture comparisons, 512 exercise previews and 102 lesson previews. New checks cover Return and keypad Enter submission, native first-responder transfer, editor arrow protection, Left/Right navigation across topics, failed versus accepted focus requests, reading completion, saved starter/empty drafts and Data loading 66 rows beyond the old 50-row boundary.

Starting-table context is declared for every exercise. Tests verify all 516 IDs in both languages, table existence in every fixture, table order and identifier quoting. The Data query has no LIMIT. The engine's existing execution, row and memory limits remain in effect. Of the installed exercises, 457 identify existing fixture inputs and 59 expression, catalog or new-object exercises identify no starting fixture table. Those tasks show an explicit empty state. Both interface resources passed plist validation and contain 331 matching keys. The existing bilingual lesson audit passed.

## Native application checks

In an isolated learning profile, the actual app accepted an editor submission through Command-Return, moved first responder to the task pane and navigated immediately with Right. A rejected query kept focus in the editor and Left/Right retained cursor behavior. Reading visits completed immediately, and a plain Right crossed a topic boundary. The Data tab loaded the relevant table directly and continued to show its eight starting rows after a rejected query returned one row. The native screenshot showed the original book/code icons with a green outline only for successful steps.

The installed Russian app reopened at the user's existing task with the saved SQL draft and worked-solution attempt count. Its two bottom tabs and shortcut labels were localized. Data showed all 12 starting orders, and Result remained the default panel. No learner answers were submitted during this installed-profile check.

## Distribution and preservation

The arm64 app and DMG passed metadata, strict code-signature, image-checksum and SHA-256 checks. A read-only mount verified the two-icon Finder layout and Applications shortcut. The mounted executable loaded both language packs and ran a real PostgreSQL query with NULLs and duplicates. Packaging reused the helper built from the existing pinned layout package.

A private consistent SQLite backup and settings export were created before replacement. All four learning tables and settings matched the backup immediately after installation. After reopening, attempts, drafts, course position, completion flags, review flags and bookmarks matched. One normal reopened-step visit was recorded. The original data path, bundle identifier, preference domain, database schema and export format remain compatible.

Only `/Applications/SQLLY.app` version 0.3.6/build 9 remains registered. The prior installed bundle and two temporary application copies were moved to recoverable Trash. Obsolete SQLLY/QueryCraft and test-app URLs were unregistered individually. The cleanup used no global Launch Services reset and did not empty Trash. Current source and the final installer remain available.

The package uses ad-hoc signing. Developer ID signing, notarization, Intel execution and independent macOS 14 validation remain public-release work. Earlier evidence is archived in [0.3.5 verification](verification/SQLLY-0.3.5.md).
