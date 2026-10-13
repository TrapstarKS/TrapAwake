#!/bin/bash
set -euo pipefail

[[ $# == 0 || ( $# == 1 && "$1" == --purge ) ]] || { echo "usage: $0 [--purge]" >&2; exit 2; }
APP="$HOME/Applications/TrapAwake.app"
if [[ -d "$APP" && ! -L "$APP" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.trapstar.TrapAwake ]] || { echo "Wrong app; nothing removed." >&2; exit 1; }
  /usr/bin/codesign --verify --strict "$APP"
  # The one-shot command unregisters SMAppService without starting an awake session.
  "$APP/Contents/MacOS/TrapAwake" --unregister-login-item
fi
if /usr/bin/pgrep -x TrapAwake >/dev/null; then
  /usr/bin/osascript -e 'tell application id "dev.trapstar.TrapAwake" to quit'
  for ((n=0; n<50; n++)); do
    /usr/bin/pgrep -x TrapAwake >/dev/null || break
    sleep 0.1
  done
  /usr/bin/pgrep -x TrapAwake >/dev/null && { echo "App still running; nothing removed." >&2; exit 1; }
fi
if [[ -e "$APP" ]]; then
  [[ -d "$APP" && ! -L "$APP" ]] || { echo "Refusing symlink or non-directory app." >&2; exit 1; }
  rm -rf "$APP"
fi
if [[ "${1:-}" == --purge ]]; then
  SUPPORT="$HOME/Library/Application Support/TrapAwake"
  LOGS="$HOME/Library/Logs/TrapAwake"
  # Keep recovery evidence and the stable lock inode; remove only known ordinary files.
  for file in "$SUPPORT/preferences.json" "$LOGS/trapawake.log" "$LOGS/trapawake.log.1" "$LOGS/insomnia.log" "$LOGS/insomnia.log.1"; do
    [[ ! -f "$file" || -L "$file" ]] || rm "$file"
  done
fi
echo "TrapAwake removed. Recovery evidence, if any, is retained in Application Support/TrapAwake."
