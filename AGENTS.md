# TrapAwake development

TrapAwake is an independent personal fork. Do not open upstream PRs or add
automatic synchronization. Preserve LICENSE, NOTICE.md and original authorship.

The shipping app starts `TrapAwakeApp` and uses the isolated `Awake` and
`AwakeUI` files. The `Insomnia` module name and legacy source/scripts are kept
for regression coverage and historical recovery reference. Do not invoke
`SessionManager.live`, legacy `install.sh` or the legacy recovery agent from
the shipping app.

Use official process-owned IOPM assertions for awake sessions. No pmset,
sudoers, private display APIs, process signals or global preference changes
belong in the primary lifecycle. Never resume a persisted session at launch.

Tests must use injected assertion drivers, clocks and temporary directories.
Do not alter the developer machine's power settings from automated tests.
Read global Claude instructions and applicable user memory. On a Mac whose
selected developer directory is Command Line Tools, run tests with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Validate `swift build`, `swift test`, release compilation with warnings as
errors, ShellCheck, bundle signature and packaged checksums. Hardware checks
must be brief, observed and reported separately. Record unsupported or
unverified platforms in docs/trapawake-validation.md.
