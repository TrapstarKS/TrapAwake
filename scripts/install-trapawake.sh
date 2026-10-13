#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/TrapAwake.app}"
DEST="$HOME/Applications/TrapAwake.app"
[[ -d "$APP" && ! -L "$APP" ]] || { echo "Build first: scripts/build-trapawake.sh" >&2; exit 1; }
# Check a private copy so the verified bundle is the one installed.
mkdir -p "$HOME/Applications"
STAGE="$(mktemp -d "$HOME/Applications/.trapawake-install.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/TrapAwake.app"
APP="$STAGE/TrapAwake.app"
/usr/bin/codesign --verify --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.trapstar.TrapAwake ]] || { echo "Wrong bundle identifier" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" == TrapAwake ]] || { echo "Wrong executable" >&2; exit 1; }
if /usr/bin/pgrep -x TrapAwake >/dev/null; then
  /usr/bin/osascript -e 'tell application id "dev.trapstar.TrapAwake" to quit'
  for ((n=0; n<50; n++)); do
    /usr/bin/pgrep -x TrapAwake >/dev/null || break
    sleep 0.1
  done
  /usr/bin/pgrep -x TrapAwake >/dev/null && { echo "TrapAwake is still running; installation stopped." >&2; exit 1; }
fi
if [[ -e "$DEST" ]]; then
  [[ ! -L "$DEST" && -d "$DEST" ]] || { echo "Refusing non-directory destination" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")" == dev.trapstar.TrapAwake ]] || { echo "Destination belongs to another app" >&2; exit 1; }
  mv "$DEST" "$STAGE/previous.app"
fi
if ! mv "$APP" "$DEST"; then
  [[ ! -d "$STAGE/previous.app" ]] || mv "$STAGE/previous.app" "$DEST"
  exit 1
fi
echo "Installed $DEST. No administrator privileges or recovery agent required."
