# SQLLY 0.3.7 verification

Version 0.3.7/build 10 uses four distinct qualifying failed code submissions to enable the collapsed worked-solution section. Repeated code, formatting/comments, successful answers, conceptual assessments and service failures keep their existing treatment. Completed task tabs retain their original icons, use a thinner outline and have a subtle green fill. Content version 1.1.2 adds focused prerequisite teaching and practical examples without changing the course structure or task definitions.

## Complete course review

All 34 topics, 102 lessons, eleven sections per lesson in both languages, and 516 tasks were reviewed individually. The [review ledger](verification/sqlly-0.3.7-course-review.json) maps every task to visible prerequisite teaching in its own or an earlier lesson. Required explanations cannot be deferred to Go deeper or the recap. Specific additions include early column selection, date extraction/casts, NULL sorting, modifying joins, window frames, trigger OLD/NEW behavior, role fields, recursive-cycle handling and project business rules. Existing clear prose was retained; 376 English and 382 Russian section bodies were revised.

Every lesson now has a practical example with actual input context, runnable SQL, exact result columns/rows, and a short explanation of what changed. Original syntax examples and their measured result tables are retained and labeled separately. An additional cross-range review corrected a category caption, a NULL qualification, column-versus-row ordering wording and an untaught JOIN USING shorthand. English/Russian generation and teaching-order checks passed. A pre-edit baseline comparison confirmed every non-body curriculum field except content version is identical: all IDs, titles, hierarchy, prerequisites, tasks, hints, reference/check SQL, fixtures and grading policies remain unchanged. Editorial review records support ongoing review; they are not a mechanical proof of teaching quality.

## Automated checks

The full native SwiftPM run passed **105 tests in 21 suites in 378.368 seconds**. It validated all 516 reference answers, 1,020 fixture comparisons, 512 exercise previews, 102 original lesson previews and 102 new practical reading examples. Threshold tests cover zero/three/four failures, repeated and formatting-only submissions, errors, persistence, backup merging and manual reveal. Existing tests cover grading alternatives, NULLs, duplicates, numeric precision, ordering, isolation, timeouts and keyboard/data behavior.

After the final example and caption corrections, the bilingual source/baseline audit passed again, and all 102 practical examples were rerun through real PostgreSQL by `ReadingExampleTests`: **1 test passed in 20.827 seconds**. Both interface string resources passed plist validation. The release build passed the bundled-runtime architecture/dependency audit and strict code-signature checks.

## Native application and preserved progress

An isolated profile confirmed solution access stayed disabled after the first, second and third distinct failed submissions, then became enabled but collapsed after the fourth. Opening it displayed the reference answer. An accepted Command-Return submission moved focus to task navigation; completion, draft and solution eligibility survived a restart. The light native screenshot showed thin green outlines and subtle fill on the original book/code icons. Russian practical reading tables and SQL were checked in the running app; dark appearance was selected in the isolated profile. A detailed independent accessibility and appearance audit remains public-release work.

Before installation, a private consistent SQLite backup and settings export were created. All four learning tables and preferences matched immediately after replacing the bundle. Reopening the installed Russian app preserved attempts, drafts, position, completion/review/bookmark flags and preferences; only the normal reopened reading visit changed. No learner answers were submitted in the real profile. The bundle ID, data path, preference domain, database schema and backup format remain unchanged.

## Distribution

The final arm64 DMG passed image checksum and SHA-256 verification. Its read-only mount passed the two-icon Finder layout check and strict app signature validation. The mounted executable loaded both languages and ran real PostgreSQL with NULLs and duplicates. Both the mounted and installed applications contain the exact final verified course packs and practical-example resource. Packaging reused the existing pinned layout helper.

Temporary application bundles and the prior installed version were moved to recoverable Trash; obsolete SQLLY/test registrations were removed individually. The current installed copy is `/Applications/SQLLY.app` version 0.3.7/build 10. No global Launch Services reset or Trash emptying was used.

The app is ad-hoc signed. Developer ID signing, notarization, Intel execution and independent macOS 14 validation remain public-release work. Earlier evidence is archived in [0.3.6 verification](verification/SQLLY-0.3.6.md).
