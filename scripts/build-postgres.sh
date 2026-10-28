#!/bin/bash
set -euo pipefail
# Build tools are contributor requirements only. Released .apps bundle the result.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_VERSION=18.6
PG_SHA256=555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f
TASK_BUILD="${QUERYCRAFT_BUILD_DIR:-$ROOT/.build/postgres-source}"
DEST="$ROOT/Sources/SQLCore/Resources/Postgres"
MINIMUM_MACOS="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
mkdir -p "$TASK_BUILD" "$DEST"
ARCHIVE="$TASK_BUILD/postgresql-$PG_VERSION.tar.bz2"
if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --retry 3 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" -o "$ARCHIVE"
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL" != "$PG_SHA256" ]; then echo 'PostgreSQL source checksum mismatch' >&2; exit 1; fi
SOURCE="$TASK_BUILD/postgresql-$PG_VERSION"
if [ ! -d "$SOURCE" ]; then tar -xjf "$ARCHIVE" -C "$TASK_BUILD"; fi
BUILD="$TASK_BUILD/build-$(uname -m)-release"
VIRTUAL_PREFIX=/QueryCraft/Postgres
STAGE="$TASK_BUILD/stage-$(uname -m)"
INSTALL="$STAGE$VIRTUAL_PREFIX"
COMPILER_BIN="$TASK_BUILD/compiler-bin"
mkdir -p "$BUILD" "$INSTALL" "$COMPILER_BIN"
# Inject source-path mapping through a compiler wrapper instead of CFLAGS.
# PostgreSQL records CFLAGS and configure arguments in the executable; keeping
# the real developer path out of those strings also avoids leaking usernames.
export QUERYCRAFT_REAL_CLANG="$(xcrun --find clang)"
export QUERYCRAFT_SDKROOT="$(xcrun --show-sdk-path)"
export QUERYCRAFT_SOURCE_ROOT="$TASK_BUILD"
cat > "$COMPILER_BIN/clang" <<'EOF'
#!/bin/bash
exec "${QUERYCRAFT_REAL_CLANG:?}" -isysroot "${QUERYCRAFT_SDKROOT:?}" "-ffile-prefix-map=${QUERYCRAFT_SOURCE_ROOT:?}=/usr/src/querycraft-postgresql" "-fdebug-prefix-map=${QUERYCRAFT_SOURCE_ROOT:?}=/usr/src/querycraft-postgresql" "$@"
EOF
chmod +x "$COMPILER_BIN/clang"
export PATH="$COMPILER_BIN:$PATH"
cd "$BUILD"
if [ ! -f Makefile ]; then
  MACOSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS" "$SOURCE/configure" \
    --prefix="$VIRTUAL_PREFIX" --without-icu --without-readline --without-zlib \
    --without-openssl --without-ldap --without-gssapi --without-lz4 --without-zstd \
    --without-libxml --without-libxslt --without-llvm --disable-nls \
    CC=clang CFLAGS="-O2 -mmacosx-version-min=$MINIMUM_MACOS" \
    LDFLAGS="-mmacosx-version-min=$MINIMUM_MACOS"
fi
make -j "$(sysctl -n hw.logicalcpu)"
make install DESTDIR="$STAGE"
# Stock PostgreSQL's path resolver supports relocating prefix/bin, prefix/lib,
# prefix/share together. Bundle only the server, lifecycle tools and client.
rm -rf "$DEST/bin" "$DEST/lib" "$DEST/share"
mkdir -p "$DEST/bin" "$DEST/lib"
for TOOL in postgres initdb pg_ctl pg_isready psql pg_dump pg_restore; do cp "$INSTALL/bin/$TOOL" "$DEST/bin/"; done
cp -R "$INSTALL/share" "$DEST/share"
cp -R "$INSTALL/lib/." "$DEST/lib/"
# Prune developer static archives/headers and PGXS; retain PL/pgSQL and runtime
# libraries, extension control files and timezone/full text data.
find "$DEST/lib" -name '*.a' -delete
rm -rf "$DEST/lib/pgxs" "$DEST/lib/postgresql/pgxs" "$DEST/lib/pkgconfig"
# Installed binaries refer to the build prefix. Rewrite every bundled Mach-O
# dependency to a relative location and sign only after mutation.
while IFS= read -r -d '' FILE; do
  if file -b "$FILE" | /usr/bin/grep -q 'Mach-O'; then
    if [[ "$FILE" == *.dylib ]]; then install_name_tool -id "@loader_path/$(basename "$FILE")" "$FILE"; fi
    while IFS= read -r DEP; do
      if [[ "$DEP" == "$VIRTUAL_PREFIX/lib/"* ]]; then
        if [[ "$FILE" == "$DEST/bin/"* ]]; then
          NEW="@executable_path/../lib/${DEP#"$VIRTUAL_PREFIX/lib/"}"
        else
          RELATIVE="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$DEST/lib/${DEP#"$VIRTUAL_PREFIX/lib/"}" "$(dirname "$FILE")")"
          NEW="@loader_path/$RELATIVE"
        fi
        install_name_tool -change "$DEP" "$NEW" "$FILE"
      fi
    done < <(otool -L "$FILE" | tail -n +2 | awk '{print $1}')
    codesign --force --sign - "$FILE" >/dev/null 2>&1
  fi
done < <(find "$DEST/bin" "$DEST/lib" -type f -print0)
cp "$SOURCE/COPYRIGHT" "$DEST/LICENSE-PostgreSQL.txt"
python3 "$ROOT/scripts/collect-postgres-notices.py" "$SOURCE" "$DEST"
printf '%s\n' "$PG_VERSION" > "$DEST/VERSION"
printf '%s\n' "source_sha256=$PG_SHA256" "architecture=$(uname -m)" "minimum_macos=$MINIMUM_MACOS" "compiler=$(clang --version | head -1)" > "$DEST/BUILD-INFO.txt"
printf '%s\n' 'source_path_mapping=/usr/src/querycraft-postgresql' 'configured_prefix=/QueryCraft/Postgres; relocated at runtime' >> "$DEST/BUILD-INFO.txt"
echo "Bundled PostgreSQL $PG_VERSION for $(uname -m): $DEST"
otool -L "$DEST/bin/postgres"
python3 - "$DEST" <<'PY'
from pathlib import Path
import sys
runtime = Path(sys.argv[1])
leaks = [str(p.relative_to(runtime)) for p in runtime.rglob('*') if p.is_file() and not p.is_symlink() and b'/Users/' in p.read_bytes()]
if leaks:
    raise SystemExit('Developer home paths remain in the runtime: ' + ', '.join(leaks))
print('Runtime privacy audit passed: no embedded /Users/ paths.')
PY
"$ROOT/scripts/audit-runtime.sh" "$DEST"
