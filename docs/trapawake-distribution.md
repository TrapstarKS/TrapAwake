# Distribution

`scripts/package-trapawake.sh [output-directory]` builds the release product,
assembles a native app, signs it, verifies its signature and emits an arm64
ZIP, DMG and SHA256SUMS. Assembly/package staging directories are removed on
exit. `.build` is a developer cache; remove it after validation if desired.
No download/build directory is needed by the installed app.

The ZIP includes the license, credits, README and user-level install/remove
scripts. The DMG includes an Applications link. Neither installs privileged
components. The installed bundle includes LICENSE, NOTICE and CHANGELOG.

By default signing is **ad-hoc**. The initial public release is **not
Developer ID signed and not notarized**. This is stated in the README and
release notes. Gatekeeper is not weakened by the installer.

A maintainer with an Apple Developer account can set SIGNING_IDENTITY to a
Developer ID Application certificate already present in the keychain. The
build script then uses hardened runtime and a timestamp. After building,
submit the ZIP to Apple's notary service using a stored keychain profile:

```bash
xcrun notarytool submit dist/TrapAwake-0.2.1-arm64.zip \
  --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/TrapAwake.app
xcrun stapler validate dist/TrapAwake.app
spctl --assess --type execute --verbose dist/TrapAwake.app
```

Only claim notarization after Accepted and a successful stapler validation.
Repackage the stapled app and recompute checksums; do not run the default
package script afterward, which would rebuild it. Never commit credentials,
certificates, private keys, or keychain passwords. This initial release does
not execute those notarization commands.

CI tests macOS 26 and the macOS 27 preview runner. Release builds/tests run
on macOS 26. Every action is pinned to a full commit SHA. Publishing has a
separate minimal contents:write job and happens only for version tags.
Manual workflow runs produce artifacts without publishing. There is no
nightly schedule or upstream synchronization. Published releases should
name the exact source commit and distinguish local vs hosted builds. The
initial local release has checksums but no hosted provenance attestation.

For a new version: update TrapAwake-Info.plist and CHANGELOG, pass checks,
record manual limitations, commit, tag only that tested commit and push the
tag. The release workflow validates version/tag consistency before building.
Original upstream tags remain local historical references and are never
pushed as TrapAwake release tags.
