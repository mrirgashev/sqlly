# Progress storage and backup

The persistent database is `~/Library/Application Support/QueryCraft/progress.sqlite`. Its WAL and shared-memory sidecars are normal SQLite files. This database is independent of PostgreSQL practice clusters and disposable exercise data. SQLite uses WAL journaling, full synchronization, a busy timeout, and schema `user_version` migrations. The application directory is mode 0700 and the main database mode 0600.

Progress records include completion, review flags, bookmarks, visit counts, and timestamps. Attempts include a UUID, exercise ID, submitted SQL, pass/fail feedback, and timestamp. Draft SQL and the last selected step are stored separately. Queries are local user data; no telemetry or upload is needed.

Use the app's export/import actions to move progress. The documented exchange format is UTF-8 JSON:

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-10-28T10:00:00Z",
  "progress": {},
  "attempts": [],
  "drafts": {},
  "position": null
}
```

Dates are ISO 8601. Export preserves all records. Import rejects unsupported versions and files larger than 50 MB. It merges in one SQLite transaction: completion/review/bookmark flags combine with logical OR; visit counts and timestamps use the greater value; attempts merge by UUID with local records preserved on conflicts; existing local drafts and course position are preserved. Import does not silently replace local progress. Unknown content IDs may be retained for future content packs.

If the SQLite database is recognized as corrupted or not a database during initialization, SQLLY preserves it with a `damaged-<timestamp>` suffix (including available WAL/SHM sidecars), opens a fresh database, and reports recovery. Keep the damaged files if seeking recovery assistance. A newer schema is refused rather than downgraded. Disk errors should be reported; do not manually delete files as a first response.

For updates, quit the app and replace its `.app`; user data stays outside the bundle. Export first before testing unreleased builds. For manual whole-folder backups, quit the app before copying the database and sidecars. Restore only while the app is closed.

To uninstall, quit, remove SQLLY.app, then optionally remove the Application Support/QueryCraft folder after exporting desired progress. Removing the app alone preserves learning history. Appearance and editor-size preferences may also remain in the macOS defaults domain `org.querycraft.QueryCraft` (`~/Library/Preferences/org.querycraft.QueryCraft.plist`); remove that domain separately if you want to reset those preferences. macOS may retain saved window state under `~/Library/Saved Application State/org.querycraft.QueryCraft.savedState`. Remove only these SQLLY-specific items while the app is closed.

## SQLLY rename compatibility

The visible app name is SQLLY from version 0.2.0. The established bundle identifier `org.querycraft.QueryCraft` and data directory `~/Library/Application Support/QueryCraft` are retained deliberately. Renaming those internal identities would make existing progress and preferences appear lost. Export/import JSON remains compatible; visible export filenames use SQLLY.

## Learning-flow migration

SQLLY's introduction combines the former reading groups. An atomic migration maps legacy reading positions `.read.3` and `.read.5` to the same lesson's `.read.0`, merges bookmarks/review flags into the combined introduction, and marks that introduction complete only when all three previous reading groups were complete. Existing exercise completion, old rows, and drafts are retained. The recap `.read.9` remains stable. A flow-version marker prevents cleared modern flags being recreated from legacy rows on every launch. Backups add the optional `courseFlowVersion` field; older backup files remain readable, and imported legacy flags are normalized without replacing current drafts.

Language, appearance, editor size, and live-execution preferences are application settings. Switching language does not create a separate progress database or change executable SQL.


## Learning Center activity

The 0.3.0 Learning Center derives daily activity from existing saved submission attempts. Saved explicit answer attempts, including correct answers, incorrect answers, retries, and saved self-assessments, count as activity. Live previews, manual Run, reading, and navigation do not add submission activity or imply completion. No additional tracking service, database schema, or backup format is needed for this calculation.

The activity grid covers the last 182 local calendar days including today (26 weeks), with Monday-first display padding. Each day uses the local calendar and time zone; calendar arithmetic handles daylight-saving transitions. Imported attempts are deduplicated by UUID and future timestamps are ignored. Activity intensity counts submissions, while newly solved exercises count only their first successful submission in the full retained history. Streaks use that full history, with a current streak allowed to continue from yesterday. Topic rails and the course map count all learning steps, including introductions and recaps; their fractions differ deliberately from the exercises-solved total. Activity date boundaries and calculation rules are covered by automated tests; native daily counts, restart persistence, and backup merge were also inspected. See VERIFICATION.md for the actual scope.


## Worked-solution eligibility

New attempt JSON records include optional `submissionKind`: `gradedCode`, `assessment`, or `infrastructureFailure`. The SQLite schema and backup format stay compatible. Existing unclassified records and learning history are retained; only newly classified unsuccessful code submissions count toward the reveal threshold. A correct submission does not bypass the threshold.

`SolutionAccessPolicy` counts unique failed code fingerprints for the current exercise. It ignores whitespace, comments, ASCII unquoted case, empty statements, and dollar-quote delimiter renaming while preserving quoted content. This source-identity check is separate from the real PostgreSQL grader. Ten qualifying failures enable the collapsed section; revealing and loading the reference remain explicit actions. Run/Live previews do not record graded submissions. Export/import retains classification and deduplicates persisted attempt IDs.

Candidate SQL errors are attributed by execution origin and SQLSTATE. Startup, transport, fixture, reference, and system failures remain recorded for history but do not award reveal credit. State-validation references are verified on equivalent fresh fixtures before a candidate’s schema/data checks are attributed to the learner.
