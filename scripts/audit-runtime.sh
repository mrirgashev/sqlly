#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${1:-$ROOT/Sources/SQLCore/Resources/Postgres}"
RUNTIME="$(cd "$RUNTIME" && pwd -P)"
EXPECTED_ARCH="${EXPECTED_ARCH:-$(uname -m)}"
COUNT=0
while IFS= read -r -d '' NATIVE; do
  /usr/bin/file -b "$NATIVE" | /usr/bin/grep -q 'Mach-O' || continue
  ARCHS="$(/usr/bin/lipo -archs "$NATIVE")"
  if [[ "$ARCHS" != "$EXPECTED_ARCH" ]]; then
    echo "Architecture mismatch: $NATIVE ($ARCHS; expected $EXPECTED_ARCH)" >&2
    exit 1
  fi
  while IFS= read -r DEPENDENCY; do
    case "$DEPENDENCY" in
      /usr/lib/*|/System/Library/*) ;;
      @loader_path/*|@executable_path/*)
        RELATIVE="${DEPENDENCY#*/}"
        CANDIDATE="$(dirname "$NATIVE")/$RELATIVE"
        if [[ ! -f "$CANDIDATE" ]]; then echo "Missing bundled dependency: $CANDIDATE" >&2; exit 1; fi
        RESOLVED="$(/bin/realpath "$CANDIDATE")"
        if [[ "$RESOLVED" != "$RUNTIME/"* ]]; then echo "Dependency escapes the runtime: $CANDIDATE" >&2; exit 1; fi
        ;;
      *) echo "Unreviewed runtime dependency: $NATIVE -> $DEPENDENCY" >&2; exit 1 ;;
    esac
  done < <(/usr/bin/otool -L "$NATIVE" | /usr/bin/tail -n +2 | /usr/bin/awk '{print $1}')
  COUNT=$((COUNT+1))
done < <(/usr/bin/find "$RUNTIME/bin" "$RUNTIME/lib" -type f -print0)
if [[ "$COUNT" -eq 0 ]]; then echo 'No PostgreSQL native binaries found.' >&2; exit 1; fi
echo "Runtime audit passed: $COUNT Mach-O files; architecture $EXPECTED_ARCH; only bundled-relative or macOS system dependencies."
