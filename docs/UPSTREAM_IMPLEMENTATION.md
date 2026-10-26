# Implemented launcher audit

The Sikarugir-first Ports workflow now incorporates these audited patterns:

| Area | Behavior | Boundary |
| --- | --- | --- |
| Wine filesystem | Read-only reparse/junction handling, real drive maps, bounded cycle detection | No dematerialization or migration |
| Diagnostics | Check reported builtins in installed architecture directories | Missing game DLLs do not imply engine corruption; no automatic reinstall |
| Processes | Prefix plus runtime ownership, kernel executable/birth check before signals, bounded shutdown | Unidentified processes are not forcibly stopped; clones refuse uncertain activity |
| Copies | Full named environment, APFS copy optimization, exclusive staged publication | External links are retained, not copied; no in-place restore |
| Downloads | Strong ETag resume, SHA-256 verification, staged activation | New/custom versions require a digest; existing offline payloads are unchanged |
| Recipes | Curated CC0 source plans with original verification and requirements | Review only, Cosmos status always untested; no ODbL prediction import |

Ports exposes Diagnose Launch, Stop Environment and Clone Environment. File
checks run asynchronously. CLI equivalents are `repair.command diagnose`,
`repair.command apply-fix kill_wine`, `bottle.command clone source --name copy`,
`profile.command upstream-recipes` and `profile.command upstream-recipe xact`.
Pass the selected environment using the existing `COSMOS_BOTTLE`/prefix options.

Automated fixtures cover malformed/cyclic reparse buffers, remapped drives,
architecture-specific missing builtins, foreign-prefix/PID-reuse exclusion,
copy failure and existing-destination preservation, interrupted/changing HTTP
responses, checksum failures and upstream evidence separation. macOS CI builds
the native UI, runs XCTest and filesystem/process contracts, and audits the app
bundle. See the PR checks for results for the current commit.

SimCity 3000 Unlimited installation and gameplay, 32-bit engine compatibility,
SpockD3D9 rendering and interactive accessibility require actual macOS testing.
Runtime versions were not upgraded. The pre-existing unpinned DXMT Latest 0.81
URL is unavailable; use pinned 0.80. Broader uninstall policy, automatic version
history, cloud saves and additional installer task models remain future work.


Named-environment lifecycle follow-up: reset/delete now share scoped process
control, refuse linked roots/mounted folders, verify target identity after shutdown,
and detach the selected tree before protected non-following removal. On failure,
remaining files stay at the reported hidden `.cleanup-*` path; partial removal
cannot be rolled back. Nine fixtures cover external link preservation, uncertain
activity, changed identities, failure recovery, CLI confirmation and reset scope.
Per-game uninstaller cleanup remains future work. Clone is also available in
Bottles details, including environments without a registered port.
