# SQLLY

GitHub repository: [mrirgashev/sqlly](https://github.com/mrirgashev/sqlly).

A native macOS workspace for learning SQL and PostgreSQL offline. SwiftUI provides a flat topic sidebar with progress rails, numbered learning steps, persistent progress, and result tables. A dedicated Learning Center contains daily activity, a course map, submission history, and settings. English and Russian interfaces and course packs are bundled. The dark theme uses a true-black lesson canvas, charcoal surfaces, and restrained green accents; a light theme is also available. An AppKit SQL editor provides syntax highlighting and line numbers. A bundled PostgreSQL server executes real SQL against disposable learning datasets.

The application source, original lessons, exercises, fixtures, and vector icon are MIT licensed. PostgreSQL retains its PostgreSQL License and the permissive notices of components vendored upstream; see `THIRD_PARTY_NOTICES.md` and `licenses/`. This is an independent project; it is not affiliated with Stepik, Apple, or the design references.

## Install

Open the supplied `.dmg`. In its Finder window, drag **SQLLY.app** from the left onto **Applications** on the right. After copying, eject the image and launch SQLLY from Applications. The packaged development build targets Apple Silicon. Intel and universal releases require separate runtime builds and testing; they are not advertised as verified.

The development build is ad-hoc signed. No Developer ID certificate or notarization credentials were supplied. See [installation notes](docs/INSTALL.txt) and [release requirements](docs/RELEASE.md).

## Build from source

Requirements for contributors: macOS, Xcode command-line tools with a Swift 6.2 or newer compiler for the app and installer tools (this build was verified with Swift 6.4 and Xcode's macOS 27 SDK), `make`, a C compiler, Python 3 for license-inventory generation, and an internet connection for the initial official PostgreSQL source and pinned installer-helper downloads. Released app users need none of these tools.

```sh
git clone https://github.com/mrirgashev/sqlly.git
cd sqlly
./scripts/build-postgres.sh
swift test
./scripts/build-app.sh
./scripts/package-dmg.sh
./scripts/package-source.sh
```

Build products go into `dist/`. The PostgreSQL build script pins an official source release; see [engine documentation](docs/ENGINE.md). The application package has no external Swift package dependencies. A separate build-only DMG layout helper uses the pinned MIT-licensed DSStore package; it is not bundled into the application. See [third-party notices](THIRD_PARTY_NOTICES.md).

Open `Package.swift` in Xcode to work on the native app. The default build follows the host architecture. Do not combine an Intel app with an Apple Silicon PostgreSQL runtime.

## Learn

Choose a topic from the sidebar and use its numbered tabs to move between lessons and exercises. Reading steps complete when opened. Successfully completed tabs retain their book or code icon with a thin green outline and a subtle green background. From another pane, press **Command-E** to focus the SQL editor and select its text. Press **Command-Return** in the editor to submit. After an accepted answer, keyboard focus moves to the task area and plain Left/Right arrows switch steps, including across topics. Use **Shift-Command-Return** or Run Query to execute without grading. Live execution updates after a 600 ms pause and never completes a task.

The SQL workspace has **Result** and **Data** tabs. New and reset editors start with `-- Write your SQL query here`. Saved drafts open as written. Result displays every row from the task's primary starting table when the editor is blank or contains only comments. Data lets you browse the starting tables for the exercise. Expression, catalog and new-table tasks may have no starting fixture table. Custom repair/completion starter SQL appears in the task instructions. Grading executes the reference answers on independent fixtures. The installed course contains 34 modules, 102 lessons and 516 exercises.

Open **Learning Center** from the sidebar or press **Shift-Command-L**. Its calendar covers the last 182 local days and counts saved answer submissions, including retries and incorrect answers. Live previews, Run, and reading do not add submission activity. Topic rails and the course map count all completed learning steps; the exercises-solved total counts practice tasks only.

Select **English** or **Русский** in application settings. The language switch preserves step identifiers, SQL drafts, completion, and learning history. SQL keywords, identifiers, and dataset values remain unchanged. Original PostgreSQL diagnostics remain visible alongside localized application guidance.

The engine resets fixtures for each execution. Live execution never marks an exercise complete or records a graded attempt; explicit submission is required. This makes mistakes recoverable and submissions deterministic. SQL history and learning progress are persisted outside the application bundle. Core use needs no account or network connection.

## Project map

- `Sources/SQLLY`: SwiftUI workspace, observable UI state, AppKit editor.
- `Sources/SQLCore`: curriculum models, grading, persistent progress, PostgreSQL engine.
- `Sources/CPQShim`: small C bridge to the bundled libpq client library.
- `Sources/SQLCore/Resources`: original curriculum and generated PostgreSQL runtime.
- `Tests`: domain and integration checks.
- `scripts`: reproducible database, app, and DMG builds.
- `docs`: architecture, content authoring, safety boundaries, recovery, and release checklist.

Read [architecture](docs/ARCHITECTURE.md), [content format](docs/CONTENT.md), [security](docs/SECURITY.md), [contribution guidance](CONTRIBUTING.md), and [verification](docs/VERIFICATION.md) before changing those areas.

## Scope and release status

Version 0.3.8 adds Command-E editor focus and displays starting data in Result when the editor has no SQL statement. The course includes 102 practical examples with PostgreSQL-verified results in both languages. The worked-solution section becomes available after four distinct qualifying failures. Resource lookup works with both SwiftPM builders.

This repository is designed for public contribution. The current verification report and remaining acceptance work are recorded in [VERIFICATION.md](docs/VERIFICATION.md) and [CHECKLIST.md](docs/CHECKLIST.md). Unverified architecture support, notarization, and manual accessibility audits are release work, not completed claims.
