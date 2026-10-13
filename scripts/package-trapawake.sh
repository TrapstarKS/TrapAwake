#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
"$ROOT/scripts/build-trapawake.sh" "$OUT"
OUT="$(cd "$OUT" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OUT/TrapAwake.app/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
STAGE="$(mktemp -d "$OUT/.trapawake-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/TrapAwake-$VERSION"
/usr/bin/ditto "$OUT/TrapAwake.app" "$STAGE/TrapAwake-$VERSION/TrapAwake.app"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/SECURITY.md" "$ROOT/CONTRIBUTING.md" "$STAGE/TrapAwake-$VERSION/"
mkdir -p "$STAGE/TrapAwake-$VERSION/docs/assets" "$STAGE/TrapAwake-$VERSION/Resources"
cp "$ROOT"/docs/trapawake-*.md "$STAGE/TrapAwake-$VERSION/docs/"
cp "$ROOT"/docs/assets/trapawake-*.png "$STAGE/TrapAwake-$VERSION/docs/assets/"
cp "$ROOT/Resources/TrapAwake-1024.png" "$STAGE/TrapAwake-$VERSION/Resources/"
cp "$ROOT/scripts/install-trapawake.sh" "$ROOT/scripts/uninstall-trapawake.sh" "$STAGE/TrapAwake-$VERSION/"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE/TrapAwake-$VERSION" "$OUT/TrapAwake-$VERSION-arm64.zip"
mkdir "$STAGE/dmg"
/usr/bin/ditto "$OUT/TrapAwake.app" "$STAGE/dmg/TrapAwake.app"
ln -s /Applications "$STAGE/dmg/Applications"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$ROOT/README.md" "$STAGE/dmg/"
/usr/bin/hdiutil create -volname TrapAwake -srcfolder "$STAGE/dmg" -ov -format UDZO "$OUT/TrapAwake-$VERSION-arm64.dmg"
(cd "$OUT" && /usr/bin/shasum -a 256 "TrapAwake-$VERSION-arm64.zip" "TrapAwake-$VERSION-arm64.dmg" > SHA256SUMS)
echo "Release artifacts: $OUT"
