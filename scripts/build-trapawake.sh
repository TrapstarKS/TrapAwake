#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/dist}"
if [[ "$OUTPUT" == -h || "$OUTPUT" == --help ]]; then
  echo "usage: $0 [output-directory]"; exit 0
fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$ROOT"
BUILD_PATH="${TRAPAWAKE_BUILD_PATH:-$ROOT/.build}"
/usr/bin/swift build --scratch-path "$BUILD_PATH" -c release --product TrapAwake -Xswiftc -warnings-as-errors
BIN="$(/usr/bin/swift build --scratch-path "$BUILD_PATH" -c release --show-bin-path)/TrapAwake"
STAGE="$(mktemp -d "$OUTPUT/.trapawake-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/TrapAwake.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrapAwake"
cp "$ROOT/Resources/TrapAwake-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/TrapAwake.icns" "$APP/Contents/Resources/TrapAwake.icns"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$ROOT/CHANGELOG.md" "$APP/Contents/Resources/"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP"
fi
/usr/bin/codesign --verify --strict "$APP"
if [[ -e "$OUTPUT/TrapAwake.app" ]]; then
  [[ -d "$OUTPUT/TrapAwake.app" && ! -L "$OUTPUT/TrapAwake.app" ]] || { echo "Refusing non-directory app destination" >&2; exit 1; }
  rm -rf "$OUTPUT/TrapAwake.app"
fi
mv "$APP" "$OUTPUT/TrapAwake.app"
echo "$OUTPUT/TrapAwake.app"
