# SQLLY 0.3.4 verification

Version 0.3.4/build 7 ships the light icon and a ten-failure gate for coding exercises' worked solutions. The application identifier and learning-data directory are unchanged. Earlier evidence remains in [0.3.3](verification/SQLLY-0.3.3.md), [0.3.2](verification/SQLLY-0.3.2.md), and the older archived reports.

## Solution eligibility

Each coding exercise requires ten distinct unsuccessful graded code submissions. Run/Live previews, successful answers, repeated or reformatted source, comments, and infrastructure failures do not add credit. A bounded lexical fingerprint preserves quoted content and ignores source formatting; correctness is still determined by real PostgreSQL execution. Candidate SQL errors carry an explicit origin and SQLSTATE, while fixture/reference/system failures remain excluded. State-validation references run on equivalent fresh fixtures before learner validation.

The section is disabled and its answer content omitted while locked. Failure ten enables the collapsed section; reveal and loading remain explicit actions. Eligibility comes from persisted attempt metadata and survives restart/export/import. Existing unclassified history is retained without granting unlock credit; no SQLite migration or backup-format change is required. Non-coding response/rubric flows remain available.

## Automated and native verification

- Full native SwiftPM run: **93 tests in 17 suites passed in 387.922 seconds**, including all 516 reference answers, 1,020 fixture comparisons, and 512 expected-result previews.
- Focused native run: **26 tests in 3 suites passed in 11.220 seconds**.
- Default Swift Build checks: application tests **2/2 in 6.122 seconds**, domain tests **24/24 in 11.085 seconds**.
- New coverage checks zero/nine/ten failures, duplicates, lexical quoting/Unicode, successful-answer behavior, candidate versus service errors, exact source identity, restart, and overlapping backup imports. Model tests use private temporary progress and engine directories.
- The actual app was checked at zero failures, after a duplicate, through nine distinct failures, and after failure ten. Its native accessibility tree confirmed disabled through nine, enabled but collapsed at ten, and answer code visible only after explicit expansion. Restart retained eligibility with the section collapsed.
- After clean shutdown, all four user learning tables were restored and compared exactly with a private pre-test backup. Test attempts/drafts/visits were removed; existing learning data was preserved.

## Icon and distribution

The original AppKit artwork now uses a warm near-white background, dark cylinder strokes, and a deeper green accent. Large and 16–128px previews were inspected, all standard 16–1024px ICNS representations were generated, and iconutil decoding passed. The mounted app and volume icons match the approved light preview byte for byte.

Optimized app assembly passed for **arm64, 0.3.4/build 7**, including strict deep signing and metadata checks. The final DMG passed integrity and SHA-256 verification. A private read-only mount verified the Finder two-icon installation layout, Applications symlink, both 516-task course packs, 316 matching localization keys/format arguments, a 715-file privacy scan, and 39 native runtime dependencies. The mounted app's real PostgreSQL diagnostic passed NULL/duplicate-row checks and shut down its temporary engine. The audit mount was detached.

Local cleanup moved three legacy app bundles, six older DMGs and their six checksums, plus the temporary 0.3.4 build app to recoverable Trash. Only three exact app registrations were removed from Launch Services. Source ZIPs, repository files, preferences, learning data, and private backups were excluded. All four learning tables still matched the original baseline after cleanup. The only retained installable distribution is the latest 0.3.4 DMG; installation is left to the user.

The source archive is regenerated after this report and checked for ZIP CRC, exact source parity, artifact/privacy exclusions, and matching SHA-256. Remote results are available in [GitHub Actions](https://github.com/mrirgashev/sqlly/actions/workflows/ci.yml); local checks do not establish a remote outcome.

The deliverable remains an Apple Silicon development package with ad-hoc signing. Developer ID signing, notarization, Intel execution, and independent macOS 14 validation remain public-release work.
