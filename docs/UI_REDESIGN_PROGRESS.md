# UI redesign implementation progress

The first working slice of [UI_REDESIGN_PLAN.md](UI_REDESIGN_PLAN.md) adds the new
workspace shell and shared selected-game commands. The full redesign remains in
progress; existing tools stay reachable while their dedicated screens are rebuilt.

## Implemented

- Permanent Library, Installations, Environments, Components and Activity sidebar.
- Combined read-only catalog of saved launchers and standalone Ports. Namespaced
  source IDs preserve duplicate titles, source records and exact launch targets.
- Library search/source filtering and selected game details; standalone launch,
  settings editing, Mac-app creation, filesystem checks/reveal and diagnosis.
- Add Installed EXE uses the existing validated creation flow, then selects the
  newly created record. Existing files/settings are not migrated.
- Install and continuation actions are directly available without Steam setup.
- Context menus, toolbar, keyboard and Game menus share capability checks and
  selected-game execution. Missing/stale selection never falls back to another
  saved launcher. Menus follow the focused workspace window.
- Native Settings with a temporary previous-interface switch, neutral first-run
  messaging, restrained navigation, and a compact active-operation strip.
- Destination back/forward history, last-destination restoration and Command-F
  Library search. Additional tools open inline so their sheets can present normally.
- Existing environment/component views appear in their new destinations. Activity
  presents current/latest output without claiming persistent operation history.

## Action inventory and transitional locations

| Existing action family | New entry point / preserved access |
| --- | --- |
| Port create/launch/edit/build/files/diagnose | Library, Add Game, Game menu |
| Port stop/clone/delete and distribution overrides | More → previous interface, retained Ports actions; environment clone/stop via existing tools |
| EXE/MSI install/resume/retry | Add Game and Installations, existing tracked Terminal handoff |
| Saved-profile launch/reveal | Library; existing launch service and selected shared environment |
| Saved-profile favorites, source sync/detect/build, presets and compatibility reports | More → Game Presets & Compatibility; previous interface retains all original commands |
| Store imports and included launchers | More → Store Import & Advanced Tools |
| Environment creation/settings/clone/reset/delete/files | Environments and File → New Environment |
| Wine/graphics downloads, Spock and user-supplied GPTK | Components; existing download/settings sheets |
| Registry/dependency recipes and upstream review | More → Store Import & Advanced Tools and previous environment tools |
| Steam setup/settings/verification and advanced maintenance | More → Steam Setup & Settings; previous interface retains original setup and menus |
| Logs and active Terminal operation output | Activity; existing recovery banners/job tracking |
| Update checks/help | Native Cosmos/Help menus |

The previous interface is accessible from More and native Settings. It is a
temporary development fallback, not the final navigation design. Backend feature
parity is preserved by that access; moving every advanced action to a native new
destination remains work before removing the fallback.

## Remaining phases

- Complete native execution/progress and post-setup EXE selection; the staged
  wizard currently uses the tracked Terminal/Windows installer handoff.
- Complete compact grid/list/inspector layouts and favorites/recents.
- Move all saved-profile and per-environment advanced actions into shared commands.
- Replace inherited environment/component views with the designed detailed screens.
- Persistent Activity history, richer native Settings and sanitized diagnostic export.
- Visual screenshot review and interactive keyboard/VoiceOver/layout tests.
- Real SimCity, x86/WoW64 and Spock gameplay/renderer validation.

Tests cover duplicate source IDs/titles, preserved architecture/environment/path,
selection absence, Steam-independent capability checks, busy/host restrictions
and catalog search. Native snapshots include first launch and Library light/dark.
CI compilation, bundle and regression checks must pass for the final commit.

## Installation wizard follow-up

Library and Installations now open a four-step Game → Destination → Requirements
→ Review wizard. It accepts EXE/MSI, names a dedicated environment or explicitly
reuses an existing WoW64 environment, and previews the actual Windows destination
through the read-only filesystem bridge before starting setup. The default folder
is explicit, so a new installation does not need a second folder chooser in Terminal.
Existing-prefix mappings are respected; uninitialized defaults are labeled as such.

Continuation locks the saved title/environment and omits a folder override unless
the user chooses relocation. Retry includes setup; Finish never runs it. Source
headers, destination mappings and missing saved folders are checked off the main
thread, without creating environment data. Back/error paths retain the form.

Terminal AppleScript acceptance is now collected asynchronously through the shared
command runner. Nonzero exit and launch failure retain the wizard, display the
error, and clear only the rejected handoff's pending tracking. Directory preparation
failure no longer leaves a pending job behind. Accepted handoff starts the existing
job watcher; it is not a claim that setup or gameplay succeeded. The Windows
installer and final game chooser remain interactive in the tracked helper.

Native fixtures cover source validation, MSI/DLL rejection, explicit environment
reuse, immutable recovery identity, default arguments, actual D: mappings,
read-only new-prefix preview, disconnected destinations, and accepted/rejected/
large-output handoffs. Snapshots cover all four stages and a fresh installation.
