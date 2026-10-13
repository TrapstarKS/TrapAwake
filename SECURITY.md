# Security

TrapAwake uses process-owned IOPM assertions without root, pmset writes,
sudoers grants, private display calls, or a launchd recovery job. macOS owns
the assertion lifetime; the app's session file is diagnostic evidence and
never permission to restart a session. Critical heat and a nonzero critical
battery cutoff cannot be disabled by Unlimited mode.

Persistence is atomic and app files are created owner-only. A lifetime
kernel lock prevents two cooperating TrapAwake instances from sharing a
session marker. ACLs and a process already running as the same user are not
an isolation boundary. The app is not sandboxed. Logs are local and rotated;
review them before sharing. No account, telemetry or analytics is present.

A failed release keeps the assertion ID for retry and preserves its marker.
A failed marker clear keeps recovery evidence. Interrupted/unreadable
markers are archived only after explicit acknowledgement while inactive.
The kernel removes assertions on process exit; the app never resumes one
on launch or reboot. Other apps' assertions and system safety policies remain
under their owners' control.

Initial artifacts are ad-hoc signed and not notarized. Verify checksums and
origin; use Apple's per-app approval UI if appropriate. Never disable
Gatekeeper globally. Developer ID signing and notarization requirements are
in docs/trapawake-distribution.md. A signature does not establish absence of
bugs. This fork does not inherit validation claims for hardware behavior
from historical Insomnia releases.

Report suspected vulnerabilities to this repository's Security Advisories
if private reporting is enabled. Otherwise open an issue requesting a
private contact, without secrets or exploit details. There is no response
SLA. Do not publish passwords, private logs, keychain material, or information
about unrelated applications. Test reproductions with fake drivers and
isolated data, never by changing someone else's power state or processes.

The historical Insomnia security model is retained in
[docs/upstream/SECURITY.md](docs/upstream/SECURITY.md); it describes legacy
components that are not invoked by the shipping TrapAwake app.
