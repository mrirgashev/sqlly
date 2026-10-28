# Execution safety and trust boundaries

Learner queries are arbitrary SQL and may be incorrect or destructive. SQLLY executes them in a fresh database seeded from trusted bundled fixtures, under a learner role with no superuser, role creation, database creation, replication, or server-file privileges. Course content and SQLite progress never live in that database. A learner may change or drop exercise objects without losing course progress.

The server binds to a private owner-only Unix-domain socket with generated credentials; it does not expose a TCP port. The restricted role cannot create unrestricted extensions, elevate its role, run server programs through COPY, or use privileged server filesystem functions. The engine and C bridge handle real PostgreSQL execution; UI code does not implement SQL semantics.

Limits include a server statement timeout of approximately three seconds, an outer execution deadline, row/byte caps for displayed results, and restricted execution configuration. The engine serializes practice work and cleans up temporary databases. `work_mem` is a per-operation default, not an absolute memory limit for the PostgreSQL process. A 64 MB temporary-file budget and the execution deadline reduce runaway work but do not provide a strict disk or resident-memory quota. Multi-fixture submissions evaluate independent candidate and reference environments to avoid state leakage and simple hardcoded answers.

These controls mitigate mistakes and common hostile queries, but the app and bundled PostgreSQL process run as the same macOS user. Database privilege isolation is not an OS sandbox. PostgreSQL vulnerabilities, trusted fixture authoring mistakes, and resource-exhaustion techniques outside tested limits require review before public release. This development build does not claim formal sandboxing or a completed independent security audit. Do not use it to process secrets or import untrusted executable course packs.

Security tests must cover role reset/escalation, filesystem read/write, COPY PROGRAM, extension creation, database/server administration, sleeping/recursive queries, oversized results, errors, transaction boundaries, and failure cleanup. A learner-controlled `SET` must not silently disable enforced limits. Verify that runtime credentials do not appear in logs, exports, or source.

Report security problems privately to the project maintainers once a public security contact is established. Do not include personal progress or private data in public issues.

## Live execution

Live previews are debounced for 600 ms and use the same disposable databases, restricted learner role, execution deadline, and result limits as manual Run. Superseded results are suppressed and only the newest pending request is retained; edits do not enqueue an unbounded series of database jobs. Automatic preview success does not award completion or create a graded attempt. Explicit submission remains a separate, isolated grading operation.
