# PostgreSQL execution environment

## Architecture decision

The release bundles an actual PostgreSQL server rather than a SQL evaluator in Swift. The selected runtime is PostgreSQL **18.6**, built from the official source release. Maintenance checks on 28 October 2026 found PGlite and Postgres.app active and unarchived in their upstream repositories; PostgreSQL 18 remains a supported stable major version. PostgreSQL is mature, actively maintained, runs on macOS, supports PL/pgSQL, schema design, transactions, indexes, JSONB, arrays, recursive CTEs, window functions, views, triggers, partitioning, and the SQL semantics taught by the course. Its [PostgreSQL License](https://www.postgresql.org/about/licence/) allows redistribution with retained notices.

Alternatives reviewed:

- [PGlite](https://pglite.dev/docs/) packages PostgreSQL in WebAssembly and can run locally in JavaScript. Its documented single exclusive connection model complicate teaching concurrent connections and server administration. A native server provides broader standard PostgreSQL behavior and removes a JavaScript runtime from execution. PGlite's small footprint is attractive, but easy embedding is not the decisive requirement.
- [Postgres.app](https://postgresapp.com/documentation/) demonstrates local macOS PostgreSQL distribution and bundles additional extensions/dependencies. This project builds a minimal pinned upstream runtime directly so the source, options, notices, and architecture are explicit; it does not require users to install Postgres.app.
- SQLite is unsuitable as the PostgreSQL teaching engine because its data types, syntax, functions, query planner, and concurrency differ. SQLite is used only for local progress.

The alternatives are license-compatible in principle: PGlite documents dual Apache 2.0/PostgreSQL licensing, and Postgres.app bundles separately licensed components that would need individual review. Neither alternative is redistributed here.

Official [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/) is the authority for SQL examples. Build requirements and flags follow the official [installation documentation](https://www.postgresql.org/docs/18/installation.html).

## Reproduction and redistribution

Run `scripts/build-postgres.sh`. The pinned source archive SHA-256 is `555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f`. The script installs into `Sources/SQLCore/Resources/Postgres/{bin,lib,share}`. The app has no dependency on a Homebrew prefix or system PostgreSQL install.

The minimal build disables ICU, readline, zlib, SSL, LDAP, GSS, LZ4, Zstandard, XML/XSLT, LLVM, and other optional external libraries. Supported core PostgreSQL SQL semantics remain real; optional features needing those libraries are outside this distribution. In particular, ICU collation behavior and those compression/SSL integrations are not available. Local private socket traffic does not require TLS. Retained tools include `postgres`, `initdb`, `pg_ctl`, `pg_isready`, `psql`, `pg_dump`, and `pg_restore`; the learning UI does not expose unrestricted command execution.

Library install names are made relative to the bundled runtime. Every retained Mach-O dependency must be either bundled or a macOS system library. Preserve PostgreSQL's COPYRIGHT text and vendored-component license notices with the runtime. No optional external dylibs are bundled, but the PostgreSQL source itself contains permissively licensed third-party components; see the retained notices and license inventory. Architecture support is only the architecture actually built and launch-tested; the current development package is arm64.

## Lifecycle and isolation

On first execution the engine initializes a private, ephemeral per-launch cluster under `~/Library/Application Support/QueryCraft/Engine`. PostgreSQL listens on a private random Unix-domain socket, not TCP. Directories are owner-only. Authentication uses generated credentials, never a fixed credential shipped in source. A mode-0600 temporary password file is supplied to `initdb` and removed after initialization; credentials then remain in process memory. The administrator connection provisions fixtures; submitted SQL executes as a restricted learner role.

Each execution receives a new practice database. Candidate and reference runs receive independent equivalent fixtures. Queries cannot alter the SQLite progress database or bundled course files through normal SQL privileges. Resetting practice does not erase learning progress. The engine serializes operations and disposes practice databases after use. Scripts use PostgreSQL's simple-query protocol and return the final statement's result. Commands such as `VACUUM` must be submitted by themselves outside a transaction; batching them with ordinary statements in one message creates an implicit transaction and PostgreSQL rejects it. State validation uses a separate connection after the submitted script ends, so only committed changes are checked.

Normal termination stops PostgreSQL. Startup examines prior sessions and only attempts cleanup when the recorded owning app process no longer exists. Practice data is disposable; progress is not. Do not run a second manual server against the same data directory.

## Recovery and upgrades

An interrupted app or server can leave an engine session folder. Quit all SQLLY copies before recovery. Export progress if possible. The engine should stop and discard orphaned disposable clusters on a subsequent launch. If manual intervention is necessary, identify only SQLLY-owned server processes and engine directories; never terminate another PostgreSQL installation or delete arbitrary database directories.

A PostgreSQL major-version change requires a fresh disposable cluster, not an in-place binary swap against an old data directory. The current ephemeral design can rebuild practice data from bundled fixtures while preserving SQLite progress. Retain backups when changing progress formats. A public release must test interrupted launch, shutdown, crashes, disk-full errors, and upgrades on separate accounts.

See [security boundaries](SECURITY.md), [progress backup](PROGRESS.md), and [verification evidence](VERIFICATION.md).
