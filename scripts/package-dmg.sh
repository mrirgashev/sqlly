#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/dist/SQLLY.app"
if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi
VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
ARCH="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/SQLLY" | /usr/bin/tr ' ' '-')"
DMG="$ROOT/dist/SQLLY-$VERSION-$ARCH.dmg"
STAGE="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"
MOUNT="/Volumes/SQLLY-Build-${STAGE##*.}"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then
    /usr/bin/hdiutil detach "$MOUNT" >/dev/null || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
CONTENTS="$STAGE/contents"
mkdir "$CONTENTS"
/usr/bin/ditto "$APP" "$CONTENTS/SQLLY.app"
ln -s /Applications "$CONTENTS/Applications"
cp "$ROOT/docs/INSTALL.txt" "$CONTENTS/.Installation.txt"
cp "$APP/Contents/Resources/AppIcon.icns" "$CONTENTS/.VolumeIcon.icns"

# A separate, pinned Swift package writes the Finder layout. It is a build tool,
# not an application/runtime dependency. No GUI scripting or Python is needed.
LAYOUT_BUILD=(swift build --package-path "$ROOT/scripts/DMGLayout" --scratch-path "${DMG_LAYOUT_SCRATCH_PATH:-$ROOT/.build/dmg-layout}")
"${LAYOUT_BUILD[@]}" -c release --product SQLLYDMGLayout
LAYOUT_BIN="$("${LAYOUT_BUILD[@]}" -c release --show-bin-path)/SQLLYDMGLayout"

# The picture alias records volume/file IDs. Generate it on the writable image
# itself, then preserve that filesystem while compressing the final disk image.
IMAGE_KB=$(( $(/usr/bin/du -sk "$CONTENTS" | /usr/bin/awk '{print $1}') + 32768 ))
/usr/bin/hdiutil create -size "${IMAGE_KB}k" -fs HFS+ -volname "SQLLY" -srcfolder "$CONTENTS" -ov -format UDRW "$STAGE/writable.dmg"
/usr/bin/hdiutil attach -nobrowse -noautoopen -owners off -mountpoint "$MOUNT" "$STAGE/writable.dmg" >/dev/null
MOUNTED=1
"$LAYOUT_BIN" prepare "$MOUNT"
"$(xcrun --find SetFile)" -a C "$MOUNT"
/usr/bin/codesign --verify --deep --strict "$MOUNT/SQLLY.app"
sync
/usr/bin/hdiutil detach "$MOUNT" >/dev/null
MOUNTED=0
rm -f "$DMG"
/usr/bin/hdiutil convert "$STAGE/writable.dmg" -format UDZO -o "$DMG"
/usr/bin/hdiutil verify "$DMG"
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "$CODE_SIGN_IDENTITY" != '-' ]]; then
  /usr/bin/codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${CODE_SIGN_IDENTITY:-}" || "$CODE_SIGN_IDENTITY" == '-' ]]; then
    echo 'Notarization requires CODE_SIGN_IDENTITY for an Apple Developer ID Application certificate.' >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
cd "$ROOT/dist"
/usr/bin/shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
echo "Disk image: $DMG"
