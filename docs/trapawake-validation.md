# TrapAwake 0.2.0 validation

Validated locally on October 13, 2026: Apple Silicon (arm64), macOS 26.3
(25D125), Xcode 26.6 (17F113), Swift 6.3.3. Deployment minimum: macOS 26.
These are observed results, not a hardware-safety certification.

## Automated coverage

- Debug compilation and release compilation with warnings treated as errors passed.
- The full 1,263-case suite was executed twice with isolated XCTest workers.
  The first run exposed inherited locale, animation scheduling and teardown
  issues, plus short fake-command timeouts under concurrent compilation.
- Locale-dependent Security/Keychain expectations now use typed failures or
  the current native message. Pure UI tests no longer assume NSApp exists.
  The partial-animation state test starts from a controlled first stage.
- The second full run passed 1,262 cases and exposed one further one-second
  success-fixture timeout. Two AppEncoded success scenarios now have a
  five-second fake-command budget; timeout tests and production limits stay
  unchanged. The corrected scenarios and affected suites passed on rerun:
  34 tests, zero failures, including all 29 new Awake tests.
- Final packaging/isolation/core verification passed 54 tests with zero
  failures after adding namespace isolation to the test loader.
- Test data is relocated before discovery for both the historical Insomnia
  and new TrapAwake namespaces. Core assertion operations use fake drivers;
  clocks, stores, release failures, power snapshots and concurrent ownership
  are injected. No automated test changes real power settings.
- ShellCheck, bash syntax, workflow YAML syntax, plist validation and
  `git diff --check` passed. The original MIT license is byte-for-byte unchanged.

The new tests cover Unlimited without a fabricated end date; monotonic expiry
and extensions; invalid/partial preference updates; separate display policy;
partial assertion acquisition/release; failed cleanup and quit retries;
unreadable, symlink and interrupted markers; owner-only atomic writes;
single-instance locks; mandatory battery/critical thermal protection;
serious-heat configuration; and unavailable battery monitoring.

## Observed installed-app checks

| Check | Result |
| --- | --- |
| Install to ~/Applications without root, verify signature and arm64 executable | Passed |
| Launch/reopen menu controls, native Settings and origin credits | Passed |
| Unlimited acquisition | One PreventUserIdleSystemSleep assertion, no deadline |
| Display switch during active session | A separate PreventUserIdleDisplaySleep assertion appeared; system hold remained |
| End session | Both owned assertions removed; marker cleared |
| Timed preset and custom 1-minute session | Countdown advanced; 1-minute expiry released assertion and cleared marker |
| Close options/settings | Session remained active |
| Return / Escape / Command-Q | Start, close UI, graceful quit observed |
| Force quit during Unlimited | Owned assertion disappeared immediately; interrupted marker remained |
| Relaunch after force quit | Inactive, explicit acknowledgement shown; no automatic assertion acquisition |
| Recovery acknowledgement | Marker archived; controls became available |
| Graceful quit from active session | Process exited, assertion and active marker removed |
| Global power settings | pmset -g custom was byte-identical before and after every observed session check |
| Actual screenshots | Menu, timed session and Settings captured from the installed app |
| ZIP/DMG and SHA256SUMS | Generated locally and verified |

## Limits and release origin

Critical battery and thermal events were tested with injected snapshots;
we did not drain the battery, create thermal stress, physically reboot,
change global display settings, or attempt unsupported closed-lid operation.
Actual login-item registration was not toggled; its existing mocked service
suite remains covered. Other applications and existing settings can prevent
idle sleep independently of TrapAwake.

macOS 27 is configured as a CI target. No local macOS 27 or Intel hardware
validation is claimed. The initial release is built locally, ad-hoc signed,
and not Developer ID signed or notarized. It has checksums, with no hosted
build-provenance attestation claimed. Gatekeeper was not disabled, and
first-launch behavior of a quarantined browser download is not claimed tested.

Historical Insomnia results in docs/release-validation.md belong to its
original maintainer and releases; they are not evidence for TrapAwake.

## Hosted verification after publication

[CI run 38376757794](https://github.com/TrapstarKS/TrapAwake/actions/runs/38376757794)
for source `8d986df62e4117f06a310c8da836a694aea83428` completed successfully on
both macOS 26 and macOS 27. Each runner executed 1,263 tests with 27 conditional
skips and zero failures; release compilation and packaging also succeeded.
These are hosted automated results, not local hardware validation.

The separate tag-release run exposed a Bash 3.2 race in a historical fake
sudo: a TERM trap could be copied into a newly forked sleep child. Its
signal-logging fixture now waits with a builtin read on a private FIFO, so
it forks nothing after publishing readiness. Production supervisor code,
timeouts, lock ownership and published 0.2.0 application assets are unchanged.
The supervisor-lifetime and slow-poll timeout tests passed after this correction.

[CI run 38415871826](https://github.com/TrapstarKS/TrapAwake/actions/runs/38415871826)
and [release-build run 38415863602](https://github.com/TrapstarKS/TrapAwake/actions/runs/38415863602)
for `09f1f6c8a66711267ca200589632003d493393cf` both passed after that fixture
correction. The published 0.2.0 assets remain unchanged.

## 0.2.1 inline menu bar controls

Seven new menu-bar tests passed with fake assertion drivers and temporary
storage. They cover combined duration and extension limits, empty input,
digit focus/backspace, preserving the assertion when adding time, Unlimited
conversion, failed-stop gating and direct native child right/Control/Option
click routing. Release compilation passed with warnings treated as errors.
The 0.2.1 bundle was installed to `~/Applications`, its signature verified,
and its process observed running inactive without a power assertion.

An unrestricted parallel run scheduled all 1,270 cases and failed 48
historical script/UI tests. Inspection found one-second fixture-local fake
command deadlines expiring under load and animation-settle assertions
running before layout completed. Fixtures have unique temporary roots and
do not depend on an installed Insomnia copy. No production timeout or power
behavior was changed in response.

A two-worker repeat completed all 1,270 scheduled cases with two historical
failures: the supervisor signal-count fixture and a legacy fold-animation
wait. A subsequent serial run of those two cases plus all seven new menu-bar
tests passed nine tests with zero failures. The parallel runs are not
reported as clean full-suite passes. Hosted CI uses normal serial
`swift test`; its result is recorded separately when available.

These event tests call the native controls with synthetic NSEvents; they
do not establish physical hit-testing, live keyboard focus or VoiceOver
behavior. The UI automation surface cannot directly select this windowless
status item. Physical interaction on macOS 26 and 27 and VoiceOver remain
unverified for the new inline controls. The earlier observed assertion and
recovery checks above belong to 0.2.0; its core lifecycle is unchanged.
