# Architecture

The executable product is TrapAwake. The internal Insomnia module name is
retained to keep the original utility and regression test sources intact.
`main.swift` selects only TrapAwakeApp, except for a login-item unregister
command used by the uninstaller. It does not instantiate the legacy
SessionManager, AppServices, lid actions or recovery agent.

`AwakeController` owns one optional system assertion and one optional display
assertion. Its synchronous main-actor transitions avoid interleaved start,
stop, protection and preference operations. Unlimited has a nil end date;
timed sessions use an injected ContinuousClock deadline. Persisted dates
are diagnostic only. Extending a timed session persists the updated marker
before changing its live deadline.

Start: validate preferences and power → record marker → acquire system
assertion → optionally acquire display assertion. Acquisition failures roll
back owned assertions and marker; failed rollback retains ownership/evidence.
End: release owned assertions → remove marker. A failed release retains its
ID for retry. A failed marker removal reports recovery instead of hiding it.

`AwakeStore` reuses Insomnia's private file and JSON encoding utilities.
Preferences and markers are atomically renamed into place. `AwakePaths`
isolates the fork's storage. A process-lifetime `RecoveryLock` handle on
`.owner.lock` prevents multiple cooperating app instances from racing on
that storage. The stable lock inode is never removed during normal use.

`PowerMonitor` is the reused native IOKit/thermal event source. It is not the
legacy FloorRuleDriver: the fork never invokes its pmset Low Power Mode
behavior. Protection transitions release assertions. Battery reads retry
only while unreadable; no heavy process polling is present. Critical thermal
protection is mandatory; serious thermal protection is configurable.

AppKit owns the status item, native context menu, inline duration controls,
attention popover and settings window. SwiftUI owns settings and attention
controls. Left-click reveals days/hours/minutes; Return starts a timed
session or extends an existing timed session. Right/Option/Control-click
opens Unlimited, presets and Stop. The pure legacy DurationInput and
nonactivating KeyCatcherPanel are reused without the legacy SessionManager.
The combined duration is checked against the assertion lifecycle's 30-day
limit. Closing UI leaves assertions intact. Settings persist immediately
only when validation and storage succeed. LoginItem uses SMAppService and
its original install-identity healing behavior; launching the app does not
start a session.

Kernel-owned assertions are removed on process exit, including force quit.
This avoids the original engine's persistent global state and its need for
a periodic privileged backstop. A crash marker prompts acknowledgement at
next launch and is archived. No assertion or old system setting is restored
from a diagnostic marker. This model cannot maintain wakefulness after the
app has died, and does not override deliberate sleep or clamshell policy.

The legacy source, scripts, tests, icon and design documents remain as
historical/recovery reference. They are not supported TrapAwake features.
Their tests still exercise temporary fakes, and current packaging does not
ship the old recovery script, sudoers installer or launchd plist.
