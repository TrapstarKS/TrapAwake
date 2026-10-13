# Contributing to TrapAwake

This repository is an independent fork; contributions target TrapAwake,
not krishhgg/Insomnia. Keep changes focused on stable, simple awake sessions.
Preserve original notices, credits and historical authorship.

Use full Xcode with Swift 6.2+, Apple Silicon and macOS 26+. Run:

```bash
swift build
swift test
swift build -c release --product TrapAwake -Xswiftc -warnings-as-errors
shellcheck scripts/*trapawake.sh
scripts/package-trapawake.sh
```

When Command Line Tools is selected, set DEVELOPER_DIR for these commands.
Tests must use fake assertion drivers, injected continuous/wall clocks,
and temporary stores. Never run privileged or hardware-changing commands
from automated tests. Check failure/rollback paths and preserve recovery
markers if cleanup fails. Critical protections remain mandatory.

The module and historical test directory are named Insomnia to retain
regression coverage. The executable product and app are TrapAwake. Only the
Awake controller and AwakeUI are wired to its entrypoint. Historical workflows
are inert documentation under docs/upstream/workflows; current CI/release
workflows are under .github/workflows.

Document behavior changes and verification limits in CHANGELOG.md and
release-validation notes. Do not claim signing, notarization, hardware or
macOS compatibility that was not verified. No automated upstream sync.
