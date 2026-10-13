# Insomnia source and community audit

Inspected October 13, 2026, before implementation. Source repository:
https://github.com/krishhgg/Insomnia. Base commit:
`b6a7499c183b82eb30b5e969489e6a7420250eea`, main after the stable 0.1.0
release. The package targets macOS 26, Swift tools 6.2, and Swift 6 language
mode. There are no external package dependencies. Original MIT notice is
preserved unchanged. README, SECURITY, recovery/lid/install/release/spec
and test documentation were inspected; historical documentation remains in
this checkout and its original README/security files are under docs/upstream.

The exact-name GitHub repository search returned no TrapAwake match before
creating this fork. The name was retained for its personal identity.

## Architecture and energy audit

The original SessionManager orchestrates persistent session/state journals,
pmset sleep control, Low Power Mode, lid events, brightness/audio changes,
process freezing, App Nap settings and optional network/tmux behavior.
`performStart` writes `sleepDisabledByUs`, arms launchd, and invokes
`PmsetSleepGuard`. The latter requires a recovery transaction lock and
runs exact passwordless sudo pmset operations. `restoreAll` and launch
reconciliation assume that persistent global claim. The shell backstop
independently interprets the same claim and calls pmset. An assertion provider
cannot safely replace one method while leaving these assumptions in place.

The original installer grants the user account four exact pmset commands via
`/etc/sudoers.d/insomnia`; any process running as that user can use the grant.
Modern recovery locks cover child privileged commands, preserve incomplete
journals, bound subprocess waits and verify the sealed recovery script's
signature. Those are valuable safeguards for the legacy design. Its backstop
cannot restore every audio change or monitor thermal/battery state while the
app is absent. Private brightness/keyboard APIs and process freezes add
hardware/version-dependent recovery requirements.

The chosen source explicitly documents that `disablesleep` can revert a few
seconds after a successful pmset command on some macOS releases. Its readback
check detects this; it is not a universal closed-lid guarantee. Unlimited
cannot be represented safely by a far-future original `endsAt`: the model
and backstop assume a deadline, and optional process/power changes would
otherwise outlive the owner without timely recovery.

Decision: keep the original recovery code and regression tests as inert
reference, reuse PowerMonitor, OwnerOnly, JSON utilities, session formatting
and LoginItem, and isolate a smaller process-owned assertion lifecycle.
No pmset, launchd, private brightness, app freezing, Low Power Mode writing,
or privileged installer is invoked by the shipping TrapAwake entrypoint.
This change is justified by incompatible ownership/recovery semantics, not
by a wholesale replacement of robust utilities. No old Insomnia settings or
journal is migrated into the new fork's separate directories.

## Requested pull requests

All six were **open**, with `merged_at: null`, at audit time, and none was
present in the selected base. GitHub can populate `merge_commit_sha` for an
open PR as a candidate merge; this is not evidence it was integrated.
Diffs, current head commits, reviews and check results were inspected.

| Contribution | Author | Inspected head | Decision |
| --- | --- | --- | --- |
| [#75 Unlimited/owner recovery](https://github.com/krishhgg/Insomnia/pull/75) | PewDotDev | `0445d9cf0e28571d3c82c152ac70ca9dd5c69482` | Explicit Unlimited behavior and owner-loss safety cases adopted as requirements; implement independently with kernel assertions. No privileged code transplant. |
| [#99 CLI control](https://github.com/krishhgg/Insomnia/pull/99) | 0xRafie | `34f3f43484ed87ea29a4db8615dfdc3c4e715b5b` | Defer optional CLI control. Current request queue and manager-end fixes are useful if revisited. |
| [#96 Compact/minimal menu](https://github.com/krishhgg/Insomnia/pull/96) | Zinoo00 | `35d50f2678dcba5995766e23b9ff56bb3216c49f` | Do not import its 39-file/~4,900-line rearchitecture. Supply a smaller native status item and optional countdown. |
| [#93 macOS 27 interaction](https://github.com/krishhgg/Insomnia/pull/93) | hasin023 | `a2cec5ddfb2b8639e833a620a9cda230e57be5f1` | Do not import pointer rewriting. New AppKit status-button routing avoids the old hosted hold-to-end path. macOS27 validation remains explicit. |
| [#79 Agent Auto](https://github.com/krishhgg/Insomnia/pull/79) | cccccccccccccccnrd | `ae1d11a4bf12ead49aa41b286259e7233d8f4ded` | Defer. Broad coupling, lease/PID cleanup risks and missing recovery tests outweigh optional convenience. |
| [#72 Older macOS](https://github.com/krishhgg/Insomnia/pull/72) | novalis78 | `55ca9b1efd908f418257b0348648d261a6128f34` | Do not lower minimum to macOS15/Swift6.1 without a real compatibility need and testing. |

#75 had passing macOS26/27/lint/ShellCheck checks but was not mergeable with
current main. Its reviewed duplicate-owner-fields issue was addressed at the
inspected head. It still arms launchd and runs sudo pmset; importing just its
model/UI into the base would conflict with the old required-deadline recovery
schema. The rootless fork therefore uses nil for Unlimited and never resumes
a diagnostic marker. Single-instance locking protects local marker ownership;
macOS owns actual assertion cleanup.

#99 and #96 were mergeable and their macOS26/27 checks passed. Their inspected
head fixes cover CLI end through the manager, per-caller request files,
current error projection and responder open/dismiss/reopen behavior. They
remain additional APIs/maintenance surface beyond this fork's first scope.

#93 passed macOS27 but its macOS26 check failed an inherited recovery-supervisor
signal-count test. The remaining review concern is that the center-position
heuristic can rewrite an accurate queued click to a later pointer location.
A non-center regression does not prove that center case safe. Its early-release
hold fix is present. Open #76 is a competing interaction strategy and would
need a deliberate choice rather than combining patches.

#79 depends on nine commits from open #63. Its inspected head had ShellCheck
SC2317 and review concerns about lease duration calculated before awaiting
start, no fresh post-start deadline update, and cleanup signaling a possibly
reused heartbeat PID after reaping. Wrapper/recovery-schema regression
coverage was also missing. These findings were not assumed resolved merely
because one macOS suite passed.

#72 was not mergeable and also failed the inherited supervisor test. Its
isolated plutil callback hardening can be revisited if legacy recovery is
changed; the deployment-target reduction is not needed for the current Mac.

The API listed 32 open PRs and 16 open issues. Relevant issue context included
#57 (Auto/Always On), #60 (status click/hold), #94 (awake after ending with lid
closed), and #97 (external displays/lid). Open/closed metadata was inspected;
the deep code review was limited to the six requested contributions and the
base's energy/recovery chain. No PR was cherry-picked wholesale and no
upstream PR was created. Existing base authorship and applicable MIT terms
remain preserved.

## Initial build/test findings

The untouched base built on this Apple Silicon/macOS26.3 host. The selected
Command Line Tools lacked XCTest; the installed full Xcode26.6/Swift6.3.3
provided it. Three packaging assertions compared English localized Security
framework errors and failed on this Portuguese-language system despite
correct rejection. TrapAwake changes those assertions to verify the typed
signature-validation error while keeping tampered-bundle checks. Final
results and hardware limits are in docs/trapawake-validation.md.

Historical validation claims in docs/release-validation.md belong to the
original maintainer's releases and are not TrapAwake test evidence.
