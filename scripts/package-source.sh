#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"
STAGE="$(mktemp -d "$OUT/source-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/SQLLY"
/usr/bin/rsync -a --exclude '.build' --exclude '.swiftpm' --exclude '.git' --exclude 'dist' --exclude 'work' --exclude '.DS_Store' --include '.env.example' --exclude '.env*' --exclude '*.p12' --exclude '*.p8' --exclude '*.key' --exclude '*.mobileprovision' --exclude '*.sqlite*' --exclude 'Sources/SQLCore/Resources/Postgres' "$ROOT/" "$STAGE/SQLLY/"
/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE/SQLLY" "$OUT/SQLLY-source.zip"
cd "$OUT"
/usr/bin/shasum -a 256 SQLLY-source.zip > SQLLY-source.zip.sha256
echo "Source archive: $OUT/SQLLY-source.zip"
