# SQLLY 0.3.3 verification

Version 0.3.3/build 6 adds the requested focused learning workflow and repairs scheduling assumptions in the live-query tests. The bundle identifier and learning-data directory remain unchanged. Earlier evidence is archived in [0.3.2](verification/SQLLY-0.3.2.md), [0.3.1](verification/SQLLY-0.3.1.md), and [0.3.0](verification/SQLLY-0.3.0.md).

## Changes checked

- Selected topics use a green outline and button accessibility semantics. The native blue List selection is gone.
- Reading steps have a **Continue** button. Bookmark and review actions were removed from the workspace and Learn menu. Both course packs, help texts, and authoring generators now describe the available controls.
- The SQL workspace and its toolbar toggle appear only for coding exercises. Reading, recap, choice, prediction, and explanation steps retain their native response controls.
- Plain Left/Right arrows navigate the complete course across topic boundaries. Text editors, field editors, selected text, modified arrows, other windows, and sheets keep their native behavior.
- Command-/ toggles SQL line comments with indentation, UTF-16 selections, and native undo. A real AppKit regression test covers consecutive toggles through the actual text view, coordinator, and SwiftUI binding. It caught an NSString alias that had skipped selection restoration; the command now snapshots the original text before editing.

## Automated execution

The final full native SwiftPM run passed **67 tests in 14 suites in 390.939 seconds**. It checked all 516 reference answers, 1,020 fixture comparisons, 512 previews, engine restrictions/timeouts, persistence, localization, nine comment-transformation cases, and the actual AppKit command regression.

The focused native run, including the real AppKit regression and revised live-query tests, passed **18 tests in 4 suites in 8.615 seconds**.

The default Swift Build engine also passed its separate AppKit run (**1 test in 0.162 seconds**) and focused SQLCore run (**21 tests in 4 suites in 8.868 seconds**).

The previous GitHub run verified the resource fix and every curriculum reference, but reported 10 live-query timing issues. The tests had assumed short sleeps or a started notification meant another actor had finished. They now synchronize on observable completion, submit logically simultaneous client edits in one actor turn, and hold real PostgreSQL responses before publication. The integration tests require the actual `57014` hard-deadline error and exact backend query history. The separate engine deadline test remains intact. Production execution/grading logic was not changed by this test repair.

CI preserves the full native test log even on failure, appends a bounded summary, emits specific failure annotations, and preserves Swift's actual exit code. It also verifies the packaged app after hiding its original build cache. YAML, all shell blocks, simulated failure/exit-code preservation, summary bounds, escaping, and cache restoration were checked locally.

## Native app and user data

Optimized native SwiftPM assembly passed as **0.3.3/build 6, arm64**, including strict deep signing and metadata validation. The app's cache-hidden diagnostic passed both 516-exercise curricula, both Russian string tables, contained resources, and a real learner query with NULL, numeric precision, duplicates, and ordering.

Manual native UI checks observed the green outline, Continue, absent bookmark/flag controls, hidden editor on reading/recap/choice steps, editor appearance for coding, forward/backward topic-boundary navigation, and editor arrows retaining the current step. Consecutive Command-/ commands preserved a multiline Unicode selection and restored its SQL; Command-Z reversed each toggle as one action. Command-Return executed the edited SQL and returned the expected value `2`.

A private SQLite backup was taken before these manual checks. After clean shutdown, all four learning tables were restored and compared exactly with that baseline. No test drafts, visits, completion, or answer attempts were retained. The backup remains outside the repository.

## Distribution and remote status

The final 0.3.3 DMG passed creation, integrity, and its SHA-256 sidecar. A private read-only mount verified the two-icon Finder layout, Applications symlink, strict signature, all 715 app files for private paths, 39 arm64 runtime files/dependencies, exact source parity for both 516-task course packs, and 313 matching interface keys/format arguments per language. The mounted app's bundled-resource/PostgreSQL diagnostic passed, and the audit mount was detached. The source archive is regenerated after this report and checked for CRC, source parity, excluded artifacts, and matching checksum.

The [GitHub Actions workflow](https://github.com/mrirgashev/sqlly/actions/workflows/ci.yml) records each commit's remote outcome; local evidence does not establish a remote result.

This remains an Apple Silicon development package with ad-hoc signing. Developer ID signing, notarization, Intel execution, and independent macOS 14 validation are still release work. See [CHECKLIST.md](CHECKLIST.md).
