#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
APP_VERSION="${APP_VERSION:-0.3.2}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
SWIFT_BUILD=(swift build)
if [[ -n "${SWIFT_BUILD_SYSTEM:-}" ]]; then
  SWIFT_BUILD+=(--build-system "$SWIFT_BUILD_SYSTEM")
fi
if [[ -n "${SWIFT_SCRATCH_PATH:-}" ]]; then
  SWIFT_BUILD+=(--scratch-path "$SWIFT_SCRATCH_PATH")
fi
OUT="$ROOT/dist"
APP="$OUT/SQLLY.app"
RUNTIME="$ROOT/Sources/SQLCore/Resources/Postgres"
if [[ ! -x "$RUNTIME/bin/postgres" ]]; then
  "$ROOT/scripts/build-postgres.sh"
fi
"$ROOT/scripts/audit-runtime.sh" "$RUNTIME"
BIN_DIR="$("${SWIFT_BUILD[@]}" -c "$CONFIGURATION" --show-bin-path)"
# Remove copied resource outputs so a runtime-layout change cannot retain old files.
rm -rf "$BIN_DIR/SQLLY_SQLCore.bundle"
"${SWIFT_BUILD[@]}" -c "$CONFIGURATION" --product SQLLY
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "${BIN_DIR}/SQLLY" "$APP/Contents/MacOS/SQLLY"
if [[ "$CONFIGURATION" == 'release' ]]; then
  # Remove linker debug paths from public binaries before final signing.
  /usr/bin/strip -S "$APP/Contents/MacOS/SQLLY"
fi
# SPM resource bundles are copied intact, not flattened.
for BUNDLE in "$BIN_DIR"/SQLLY_*.bundle; do
  [[ -d "$BUNDLE" ]] || continue
  /usr/bin/ditto "$BUNDLE" "$APP/Contents/Resources/$(basename "$BUNDLE")"
done
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE-SQLLY.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
xcrun swift "$ROOT/scripts/make-icon.swift" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.querycraft.QueryCraft</string>
<key>CFBundleName</key><string>SQLLY</string>
<key>CFBundleDisplayName</key><string>SQLLY</string>
<key>CFBundleExecutable</key><string>SQLLY</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticTermination</key><false/>
<key>LSApplicationCategoryType</key><string>public.app-category.education</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 SQLLY contributors. MIT License.</string>
</dict></plist>
PLIST
# Sign inner Mach-O files before their enclosing bundle. A development build
# uses ad-hoc signatures, not a public Developer ID or notarization ticket.
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
while IFS= read -r -d '' NATIVE; do
  if /usr/bin/file "$NATIVE" | /usr/bin/grep -q 'Mach-O'; then
    if [[ "$SIGN_IDENTITY" == '-' ]]; then
      /usr/bin/codesign --force --sign - "$NATIVE"
    else
      /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$NATIVE"
    fi
  fi
done < <(/usr/bin/find "$APP/Contents/Resources" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print0)
if [[ "$SIGN_IDENTITY" == '-' ]]; then
  /usr/bin/codesign --force --sign - "$APP"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/file "$APP/Contents/MacOS/SQLLY" "$RUNTIME/bin/postgres"
echo "Application: $APP"
