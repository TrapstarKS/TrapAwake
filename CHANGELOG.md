# Changelog

## 0.2.0 — 2026-10-13

- Establish TrapAwake as an independent MIT-licensed fork of Insomnia.
- Make Unlimited / Until Disabled the default keep-awake mode.
- Add timed presets (15/30 minutes, 1/2/4/8 hours) and custom durations.
- Use process-owned IOPM assertions without administrator privileges.
- Separate system idle sleep prevention from display idle sleep prevention.
- Add a native one-click menu bar toggle and SwiftUI controls/settings.
- Preserve mandatory critical battery/thermal protection, with configurable
  battery levels and an optional earlier stop at serious thermal state.
- Record interrupted sessions without automatically restarting them.
- Isolate preferences, diagnostics, installation, and bundle identity.
- Add independent builds, ZIP/DMG packaging, checksums, and GitHub workflows.
- Retain original history, MIT notices, audited utilities and legacy tests.

Closed-lid sleep overrides, app freezing, private brightness controls,
automatic agent/process sessions, hotspot handoff, and CLI session control
are not enabled in this release. Ordinary macOS clamshell behavior remains
under system control.
