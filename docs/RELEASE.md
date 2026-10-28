# Build and release

## Development build

`./scripts/build-postgres.sh` downloads and builds the pinned official PostgreSQL source into the resources directory. `./scripts/audit-runtime.sh` rejects mixed architectures and non-system/non-relative PostgreSQL dependencies. `./scripts/build-app.sh` runs this audit, builds the Swift executable, assembles its resource bundle and `Info.plist`, strips linker debug symbols from the release executable to remove developer paths, creates the original vector icon, signs nested native code and the app, and validates its signature. Without `CODE_SIGN_IDENTITY`, signing is ad-hoc.

`./scripts/package-dmg.sh` creates a compressed disk image containing the app, a conventional Applications shortcut, and installation notes. It verifies the image and writes a SHA-256 checksum. Build output is in `dist/`.

Environment overrides:

- `APP_VERSION` (default `0.3.1`) and `BUILD_NUMBER` (default `4`).
- `CONFIGURATION` (default `release`).
- `SWIFT_SCRATCH_PATH`: an optional separate Swift build directory, useful when a release build and debug tests run independently.
- `CODE_SIGN_IDENTITY`: a certificate already in the contributor's keychain; never stored in the repository.
- `NOTARY_PROFILE`: an existing `notarytool` keychain profile. When set, the DMG script signs the image, submits, waits, staples, and validates. This is an opt-in release action and requires Developer ID signing.

The source archive and build scripts reproduce the build process with pinned PostgreSQL input; byte-identical DMGs across toolchains/hosts are not claimed because SDKs, signatures, and image filesystem timestamps vary.

These scripts do not create certificates or pretend to notarize an unsigned app. A successful local ad-hoc signature does not establish Gatekeeper trust for a downloaded public release. Apple documents per-app approval under System Settings → Privacy & Security in its [unknown-developer app guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Public releases should follow Apple's [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Finder installation layout

The separate `scripts/DMGLayout` package uses DSStore pinned to revision `6dc395837c3dc371f9c3e71794fab719db74c17a` to write Finder metadata. It requires Swift 6.2 or later (upstream macOS minimum 13), has no transitive package dependencies, and is never copied into the app. See [the retained license](../licenses/DSStore-MIT.txt). The build runs headlessly against a mounted writable staging image, writes a relative Carbon Alias for the original AppKit background, then converts the image to compressed UDZO format; no Finder automation or additional Python package is required.

The 0.3.1 image opens a composed 660×420 Finder installation window with two 112-point icons: SQLLY on the left and Applications on the right. Original retina artwork provides a clear green drag arrow and English/Russian instructions. The background, layout metadata, volume icon, and installation notes remain hidden so only the two install targets appear. The actual Finder first-open layout and drag-to-Applications installation were verified; see VERIFICATION.md. The app remains a normal bundle copied into Applications; installation does not place progress inside the disk image.

After packaging, inspect the actual Finder window, copy the app to Applications, eject the image, and launch the installed copy. Audit hidden image metadata as well as the app for developer paths. Preserve a user's pre-existing mounted image and installed app while performing QA unless replacement is explicitly authorized.

## GitHub publication

The source destination is [mrirgashev/sqlly](https://github.com/mrirgashev/sqlly). Source publication must preserve the project's MIT license and all upstream notices while excluding generated PostgreSQL binaries, app/DMG outputs, caches, progress backups, credentials, and signing material. A source push and a GitHub Release with downloadable DMG assets are separate actions; record exactly what was published. Do not claim an initial push or remote CI run before its actual result is known.

## Architecture support

The current deliverable is built for the host Apple Silicon architecture. To support Intel, build PostgreSQL and Swift code for Intel, inspect every Mach-O architecture and dependency, and launch the installed package on an Intel Mac. A universal release requires merging matching binaries and libraries throughout the runtime, preserving the correct data/support files, signing after merging, and testing both architectures. A universal Swift executable with a single-architecture database is not a universal application.

## Before a public release

- Run all automated and curriculum-reference integration tests.
- Verify clean first launch and app updates from the previous version on a separate macOS account.
- Exercise real quit, restart, interrupted execution, and engine recovery.
- Inspect light/dark appearance, window resizing, keyboard-only navigation, VoiceOver, increased contrast, and reduced motion/transparency.
- Review resource limits and filesystem restrictions against hostile queries.
- Audit all runtime dependencies with `otool -L`; no Homebrew or developer-machine paths may remain.
- Confirm each advertised architecture and minimum macOS version by running the installed app there.
- Review notices and license texts inside the runtime; retain all required notices.
- Use Developer ID signing, notarization, stapling, and Gatekeeper assessment for public distribution.
- Mount the final DMG, install by dragging to Applications, and launch that copy while offline.
- Publish source, version notes, the DMG, its checksum, exact toolchain/runtime build versions, and verification evidence.

The included GitHub Actions workflow has not been run on GitHub during this development session. The corresponding local build/test/package commands have actual execution evidence; CI hosting and runner-image compatibility require their first remote run.

Consult [VERIFICATION.md](VERIFICATION.md) for checks actually run in this development session. This checklist is not a statement that all release gates have passed.
