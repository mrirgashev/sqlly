# Third-party notices and license audit

## Original work

SQLLY's Swift and C bridge code, shell/Python build and authoring scripts, original curriculum prose and exercises, original seed datasets, vector application icon, and original disk-image background artwork are released under the [MIT License](LICENSE), explicitly chosen for this project.

No Stepik course text, exercise prompt, answer, dataset, illustration, or branding is bundled. Learning references inform workflow only. Design skill text is not distributed. The name SQLLY is a project name; trademark clearance for a public product name remains a release task.

## PostgreSQL 18.6

Source: [official PostgreSQL source archives](https://www.postgresql.org/ftp/source/).

License: [PostgreSQL License](https://www.postgresql.org/about/licence/), a permissive license allowing use, modification, and distribution with retained notices. The source release's COPYRIGHT and notices must remain in the bundled runtime. PostgreSQL also vendors permissively licensed components, including its Tcl-derived regular-expression implementation, Snowball text-search dictionaries, Unicode 16.0 tables (Unicode License V3), Ryu numeric conversion (Boost license option), timezone data (public domain), and other individually attributed source files. Their applicable notices are preserved in the runtime's `THIRD-PARTY-NOTICES.txt` and the project `licenses/` directory. The inventory retains 75 distinct upstream notice blocks plus standalone PostgreSQL, Tcl regex, Snowball, Unicode, and Boost license texts; the build regenerates these from pinned source and retained upstream license files. This includes the actual PostgreSQL server and libpq client library; do not describe the database as MIT licensed.

The minimal runtime is built without external ICU, SSL, readline, compression, XML/XSLT, LDAP, GSS, and LLVM libraries. Check the finished binaries with `otool -L`; every non-system dependency must be bundled and audited if flags change. A completed binary dependency audit alone does not cover vendored source licenses. Preserve the extracted upstream source-file notices as well as the main PostgreSQL COPYRIGHT and review changes before release.

## macOS system components

SwiftUI, AppKit, Foundation, system SQLite, and system C libraries are supplied by macOS and are not copied into the repository as third-party source. System fonts are selected through macOS frameworks for interface text and original rendered artwork; no font files are redistributed. The app icon is generated from original vector paths, with no external stock artwork.

## Swift Package Manager

The application package has no external Swift package dependencies. The separate build-only DMG layout helper uses the MIT-licensed DSStore package described below. The C bridge loads the bundled libpq dynamically. No Electron, Node.js, Python interpreter, Docker image, or Homebrew runtime is included in or required by the released app. Python is used only by contributors for build-time license inventory and optional curriculum regeneration.

## Release audit

Retain this document and the PostgreSQL license with distributions. Before a public release, inspect the precise built runtime, code signatures, linked libraries, resources, source licenses, and any new packages. This record documents the current intended dependency set; final binary inspection is recorded separately in [VERIFICATION.md](docs/VERIFICATION.md).

## SQLLY database icon

The [Bootstrap Database reference](https://icons.getbootstrap.com/icons/database/) was inspected as visual inspiration; Bootstrap Icons are [MIT licensed](https://github.com/twbs/icons/blob/main/LICENSE). SQLLY's database cylinder is original AppKit vector artwork. No Bootstrap source path, SVG, font file, or copied asset is distributed.


## DSStore — build-only Finder layout helper

The separate `scripts/DMGLayout` Swift package uses [DSStore by Sindre Sorhus](https://github.com/sindresorhus/DSStore) pinned to revision `6dc395837c3dc371f9c3e71794fab719db74c17a`. It creates Finder metadata for the drag-to-Applications disk image. Upstream is MIT licensed; the exact notice is retained in [licenses/DSStore-MIT.txt](licenses/DSStore-MIT.txt).

The inspected upstream manifest requires Swift tools 6.2 and supports macOS 13 or later, with no external package dependencies. This helper and its library are build tools; neither executable nor library is shipped inside SQLLY.app. The native application's dependency/runtime requirements are unchanged. Contributors need Swift 6.2 or later to build the complete installer; app users do not need Swift or the helper.
