# Architecture

SQLLY is a native SwiftUI macOS executable with an AppKit editor bridge. It is not a web application or a browser shell. Core learning requires no hosted services or credentials.

The app follows a unidirectional state design: an observable main-actor workspace model owns UI state and calls SQLCore services. Curriculum models are immutable decoded content. Views render current state, dispatch intent, and use stable lesson/step identifiers. Native split views separate curriculum, lesson text, and SQL work.

SQLCore separates four concerns:

1. Curriculum loading validates stable original lesson and exercise content from a bundled JSON resource.
2. PostgreSQL execution manages a bundled local server and disposable exercise environments. It does not parse/evaluate SQL in Swift.
3. Grading executes both candidate and reference against equivalent independent fixtures, then compares typed result tables under explicit ordering/column policies. State-changing tasks may use a validation query after candidate SQL.
4. Progress uses a persistent SQLite database outside the app, with versioned schema and transaction-based updates. Progress is never stored inside a practice database.

CPQShim is a small C adapter to libpq. The distribution bundles PostgreSQL executables, libpq, required support files, and license material. The runtime is loaded locally, not installed in a system location, and is replaced with the app on upgrades. Database data lives outside the app.

`SQLLYResources` centralizes core and interface bundle discovery. It supports packaged-app resources and SwiftPM build/test products without hardcoding the internal bundle hierarchy produced by one build engine. Callers derive curriculum, localization, PostgreSQL, and libpq locations from the resolved bundle resources. The non-UI `--verify-bundled-resources` app mode validates the relocated package with a temporary engine, allowing CI to hide its original build cache before checking the assembled app.

`WorkspaceModel.requiresCodeEditor` controls both SQL-pane availability and live scheduling. `WorkspaceKeyboardNavigation` handles unmodified arrows only in the workspace window outside text editing and sheets; the model's full-course order supplies topic transitions. `SQLLineComments` is a Foundation-only text transformation in SQLCore, while SQLTextView owns native editing, selection, and undo. The SQLLYTests target exercises that AppKit command through its real coordinator and binding without opening learning progress.

The local server runs under the current macOS account and exposes only a private Unix-domain socket. The database role used for learner queries is restricted. This reduces database privilege and accidental damage; it is not a general-purpose operating-system sandbox. See [SECURITY.md](SECURITY.md).

A new course pack changes content and fixtures, not UI or execution internals. A PostgreSQL major upgrade requires deliberate migration/reinitialization of disposable engine data while preserving SQLite progress. A change to persisted progress requires a schema migration and export/import compatibility tests.

## Reactive execution and language

`LiveQueryController` is a SQLCore actor with a 600 ms debounce. It keeps at most one active request and the newest pending request; generations/revisions suppress superseded results. A started PostgreSQL operation remains bounded by the engine deadline, while obsolete pending work is cancelled. The main-actor workspace model also checks step identity and revision before publishing a result. Live execution does not call the grading service or update completion. Manual Run and Submit supersede pending previews. Shutdown closes the controller and engine to prevent delayed tasks restarting the server after quit.

The sidebar is deliberately flat. Course modules group related concepts, and the top numbered strip navigates every explanation, exercise, and recap. The content hierarchy remains structured for authoring, prerequisites, and stable identity.

UI localization uses maintained English/Russian `.strings` resources. SQLCore loads a matching bundled curriculum pack by `CourseLanguage`. Language, appearance, and live-execution preferences use the established app defaults domain. Stable lesson/exercise IDs keep progress shared between languages; SQL fixtures and grading policies are identical. PostgreSQL's original diagnostic text is retained and paired with localized application guidance.


## Learning Center separation

The 0.3.0 refinement introduces a dedicated Learning Center alongside the lesson workspace. Daily submission activity, a course progress map, history, and settings belong there, keeping editor controls and the topic sidebar focused. Topic progress rails and course-map fractions summarize completion of all learning steps, including introductions and recaps as well as exercises. The separate solved-exercises metric counts exercises only; automatic query success does not add completion. The current verification record tracks implementation and native checks.

Activity is a projection of persisted attempts, not a second event database. SQLCore aggregates explicit submissions using stable attempt IDs and an injected calendar/time zone, so tests can cover date boundaries and daylight-saving changes. UI views render that summary and navigate using the same stable course identifiers. Existing SQLite progress and JSON export/import remain the source of truth.
