# SQLLY 0.3.1 verification record

SQLLY 0.3.1/build 4 adds the Finder installation layout to the unchanged 0.3 application. The versioned app, image metadata, actual Finder first-open, drag installation, and installed query execution passed the checks below. Source publication is a separate operation from these local release checks.

## Preserved application evidence

The unchanged application baseline is retained in [the 0.3.0 report](verification/SQLLY-0.3.0.md), including 53 tests in 11 suites in 372.929 seconds, all 516 answers, 1,020 fixture comparisons, the final optimized native app, Learning Center behavior, real local PostgreSQL execution, and the prior disk-image/source audits. Earlier reports remain alongside it. These tests do not by themselves verify the new Finder installation layout.

The 0.3.0 DMG, source ZIP, checksum sidecars, and original reports were archived before replacement. Both archived checksums passed.

## Read-only app inspection

`dist/SQLLY.app` was absent at the start of this pass. The installed `/Applications/SQLLY.app` exists as SQLLY 0.3.0/build 3 for arm64, with identifier `org.querycraft.QueryCraft`; its strict deep signature passed. Its executable's Mach-O UUID matches the retained release-cache executable. This provides a verified reuse option for a staged copy or cached rebuild. The installed app and user learning data were not modified or launched for this inspection.

Build defaults are now version 0.3.1/build 4. Bundle and data identities remain unchanged. The packaging pass must verify the staged versioned app and actual disk image before release.

## Build-only packaging dependency

The DMG layout helper uses DSStore pinned to revision `6dc395837c3dc371f9c3e71794fab719db74c17a`. Its inspected upstream manifest declares Swift tools 6.2, macOS 13 or later, and no package dependencies. The upstream MIT license was read and copied verbatim into `licenses/DSStore-MIT.txt`; notices distinguish this build-only tool from the unchanged native application dependencies. No helper binary is intended to ship inside the app.

## App assembly checked

The optimized app was assembled from the retained release scratch as version 0.3.1/build 4. Strict deep signing and metadata checks passed. The bundled English/Russian interface retains 311 matching keys; both course JSONs exactly match source, with 516 tasks and course version 1.1.0. All 715 app file entries passed the developer-home-path scan. The retained PostgreSQL runtime passed the 39-file arm64 dependency audit. The build-only DSStore helper is absent from the app. The installed 0.3.0 application retained its prior executable hash and version. See [the app audit](verification/sqlly-release-audit.json).

## Packaging and build-tool verification

The pinned upstream DSStore suite passed **170 tests in 12 suites in 0.696 seconds**. These are build-tool dependency tests, separate from the retained 53 application tests; no new application/Core test run is implied. The custom layout helper compiled successfully.

The first packaging attempt stopped at an unsupported Apple Silicon `bless --openfolder` invocation. That invocation was removed, and the second run exited successfully, producing the compressed 0.3.1 image. The successful final image passed hdiutil integrity and SHA-256 validation.

A private read-only audit mount passed the helper's Finder-record checks: a 660×420 window, two 112-point install icons at (168,214) and (492,214), icon view, internal background alias, and hidden Finder chrome. Exactly SQLLY.app and Applications were visible; Applications resolves to `/Applications`. Hidden metadata, volume icon, bilingual installation notes, and the original two-resolution AppKit background were present. All 715 regular image files passed UTF-8/UTF-16 personal/temporary-path scans. The mounted app passed strict signature and resource-parity checks; all 39 runtime Mach-O files passed architecture/dependency inspection. A fresh private SCRAM/socket PostgreSQL 18.6 cluster executed the recursive CTE/JSONB smoke result `6|object` and was cleaned up.

The audit image detached before the integration owner's first Finder open, preserving that native test. These structural checks do not substitute for observing Finder's actual layout or installing the app. See [the image audit](verification/sqlly-package-audit.json).

## Native Finder and installation checks

The integration owner opened the final image through Finder/DiskImageMounter after the independent audit mount had detached. The first-open screenshot showed the app logo on the left, Applications on the right, the green drag arrow, bilingual retina instructions, and no extra visible files. An actual Finder drag copied version 0.3.1 over the installed 0.3.0 app, after the previous installed bundle had been backed up separately. All 715 installed file hashes matched the distribution app.

The installed application launched through native UI automation and Command-Return executed a real PostgreSQL query returning six rows. The integration owner compared all four persisted learning tables with the pre-install baseline; row values matched exactly. The image was then identified by its full `image-path` and only that release's mount was detached. The installed application remained open with its own bundled runtime. These are manual native checks, not an automated Finder/XCUITest suite.

## Source archive and repository

The canonical repository is [mrirgashev/sqlly](https://github.com/mrirgashev/sqlly). Local release checks do not establish remote CI or published GitHub release assets. No remote test or publication outcome is claimed in this packaging report.

`SQLLY-source.zip` contains **98 source, test, content, documentation, license, and pinned-package files** across **123 ZIP entries**. Python ZIP CRC/content/privacy checks passed, including the build-only helper, resolved DSStore revision, upstream MIT notice, and both bilingual 516-task packs. The source excludes Git metadata, build/check-out caches, native PostgreSQL binaries, app/DMG outputs, personal progress backups/databases, and signing material. The archive was regenerated after this final report and checklist, then rechecked with `unzip -t`, full source parity, and both basename-only SHA-256 sidecars. See [the source audit](verification/sqlly-source-audit.json).

## Release limits

The app remains an Apple Silicon development build with ad-hoc signatures unless a real Developer ID identity is supplied. No notarization is claimed. Intel, execution on the macOS 14 deployment target, independent accessibility/security review, and separate clean-machine validation remain release work. Remote CI is unverified until actually run.
