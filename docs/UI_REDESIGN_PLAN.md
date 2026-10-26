# Cosmos UI and menu redesign plan

Status: proposed implementation plan, October 26, 2026. No application UI changes
are included in this document.

## 1. Product direction

Make Cosmos a native macOS Windows-game launcher organized around **add a game,
install it, play it, and fix it when needed**. Sikarugir-style standalone games
come first. Steam is an optional source, with its own setup and health status.

Replace the current launcher sidebar plus dashboard tabs with one navigation
system. Present one game library backed by the existing launch definitions.
Keep environments and components visible and understandable. Put advanced
options inside their relevant screens rather than hiding entire destinations.

Retain the tested Wine, installer, filesystem, clone, cleanup and launch services.
This is a complete presentation/navigation redesign with deliberate service
boundaries, not a simultaneous rewrite of the emulation backend.

Success means a new user can install SimCity 3000 Unlimited from an EXE into a
chosen folder, choose its installed game EXE, and launch it again from Library
without configuring Steam or understanding profiles, bottles and ports first.
Actual game compatibility remains a separate validation gate.

## 2. Problems established by source review

| Current problem | Design response |
| --- | --- |
| Launcher selection in the sidebar competes with Launch/Games/Ports tabs | One destination sidebar; game selection lives in Library |
| Games, saved launchers, curated presets and Ports overlap | One game presentation model; presets and shortcuts are actions/details |
| Bottles and Tools disappear behind Advanced | Environments is always visible; expert fields use disclosures |
| Several general menu actions require Steam readiness | Availability follows the selected game/environment and operation |
| Initial welcome text assumes Steam installation | First launch offers Install Windows Game and Add Installed Game |
| Settings are spread across Launch, menus, downloads and disclosures | Native Settings for app preferences; contextual game/environment settings |
| Global console and Steam notices dominate unrelated screens | Activity destination plus contextual progress and relevant notices |
| Menu actions depend on selected saved profile, excluding Port selection | One selection context and shared commands across every surface |

Reviewed sources: `CosmosApp.swift`, `CosmosMenuCommands.swift`,
`CosmosAppState.swift`, `ContentView.swift`, all `ContentView+*.swift` screens,
`WinePortUI.swift`, `GameLibraryUI.swift`, and the existing UI/UX audit.

## 3. Navigation and window layout

Permanent sidebar destinations, in this order:

1. **Library** — all games, source filters, favorites and recent games.
2. **Installations** — active, interrupted and completed installation records.
3. **Environments** — named Windows environments and the existing main environment.
4. **Components** — Wine runtimes, graphics components and prerequisites.
5. **Activity** — operations, results, logs and recovery actions.

Settings opens through Cosmos → Settings… and Command-comma. Help and app updates
use standard macOS locations. No second top-level tab bar or Advanced navigation
toggle. Favorites/recent are Library filters, not another global selection list.

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Cosmos       [Back] [Forward]    Library       [Search] [+ Add Game]  │
├────────────────┬───────────────────────────┬─────────────────────────┤
│ Library        │ Game list or cover grid   │ Selected game           │
│ Installations  │                           │ [Play] [•••]            │
│ Environments   │ SimCity 3000 Unlimited    │ Status · source · bitness│
│ Components     │ Other games…              │ Environment · graphics  │
│ Activity       │                           │ Files / settings / help │
├────────────────┴───────────────────────────┴─────────────────────────┤
│ Installing SimCity…                         [View Activity]          │
└──────────────────────────────────────────────────────────────────────┘
```

Use `NavigationSplitView` with a destination sidebar, content area and optional
game inspector. At the current 960×640 minimum, collapse the inspector into a
detail destination; do not compress controls or require horizontal scrolling.
Use the existing 1100×760 default until usability testing justifies a change.
Remember sidebar width, destination, Library view mode and safe selections.
Support back/forward navigation, deep links from activity, and restoring a route
whose selected item has since been removed without falling into an empty screen.

## 4. Screen specifications

### Library and game details

- One visible Add Game button with Install Windows Game, Add Installed EXE and
  Import from Store options. Reuse this entry point from menus and empty states.
- Search title and source identifiers; expose filters for source, environment,
  favorites and attention needed. Provide grid and compact list modes.
- Cards show title, source and actionable status. Use a neutral generated cover
  when artwork is absent; artwork fetching/licensing is a separate feature.
- A selected game has one main action: Play, Continue Installation, Locate EXE,
  or Get Required Component, according to its actual state.
- Details show executable, folder, 32/64-bit architecture, environment, requested
  graphics stack, arguments, shortcut status and last operation result.
- Group secondary functions into Settings, Files and Troubleshooting sections.
  Reveal Files, Check Files, Diagnose and Open Log are reachable without leaving
  the game. Advanced overrides remain available with clear inheritance labels.
- Retain **Create/Update Mac App** as an explicit action. A Port remains a launch
  definition under the hood; it does not require a separate competing catalog.
- Distinguish Remove from Library, Delete Mac Shortcut and environment deletion.
  Removing a Library entry never silently deletes Windows files or saved games.
- Compatibility evidence identifies its source. Upstream reports, local file
  checks, launch handoff and verified gameplay must remain separate claims.

### Add Game and installation wizard

Use a reusable, resumable flow with a visible step indicator:

| Step | User decision and resulting state |
| --- | --- |
| 1. Source | Choose EXE/MSI installer, existing game EXE, or supported store import |
| 2. Destination | Title, new/existing environment, destination folder; preview actual Windows drive path |
| 3. Requirements | Show architecture and required components; explain downloads or Rosetta before starting |
| 4. Install | Launch the interactive installer; show the chosen destination and follow its actual completion |
| 5. Select game | Offer filtered installed EXEs and Browse; require confirmation rather than guessing |
| 6. Finish | Confirm game settings, optional Mac app and Play Now; show registration result |

Existing EXE import skips installation. Store imports use their supported source
workflow rather than pretending all stores use the same local installer flow.
Default standalone setup retains the tested WoW64/WineD3D baseline. Show x86
support as a requirement to verify, not as a guarantee of runtime compatibility.

Persist decisions per installation. Back navigation and validation preserve
inputs; close/cancel explains whether setup keeps running or only selection is
being dismissed. Continue Installation never reruns setup. Retry Setup is a
separate, explicit action. Disconnected destinations require reconnection or
explicit relocation; no silent replacement folder creation.

Initially retain the existing Terminal/Windows installer handoff and display it
honestly. A later native process bridge may replace Terminal after it preserves
installer completion, cancellation, output draining and restart recovery.
Do not simulate installer progress or expose a Cancel button that cannot safely
stop the particular process. Registration succeeds before offering Play.

### Installations

Show active and interrupted operations first, with title, destination, environment,
last known stage and next action. Prepared → Run Setup; failed setup → Retry Setup
or Finish if installed; awaiting EXE → Select Game EXE. Preserve legacy records
that lack new metadata and offer a clear manual continuation path.

Completed records link to the registered game. Relaunching Cosmos reconciles
saved records with actual running work; an old `installing` marker is not proof
that an installer is still running. Keep installer actions available without Steam.

### Environments

- Use the user-facing name **Environment** consistently. Explain once that this
  is an isolated Windows setup, also called a Wine bottle.
- List name, initialized state, Wine version, architecture and number of games.
  Mark the legacy main/Steam environment distinctly and preserve its location.
- Details group Overview, Games, Files, Graphics, Dependencies and Advanced.
- Provide Install into Environment, Clone, Open Folder, Diagnose and Stop.
  Keep Reset/Delete in a separate destructive group with existing confirmations.
- Show actual C:/D:/Z: mappings, registry locations, game folders and linked Mac
  folders. Unavailable drives have a reconnect/locate explanation.
- Explain shared settings versus game overrides. Changing a shared environment
  setting previews which games are affected; use a clone to isolate experiments.
- Include existing winetricks/dependency recipes, registry tools and applicable
  advanced Wine fixes. Recipe review retains original requirements/provenance.
- Preserve cleanup protections and recovery paths. Do not add an Undo claim to
  reset/delete; external links and inside-prefix saves have different outcomes.

### Components

One catalog for Wine runtimes, Rosetta requirements, DXMT, SpockD3D9,
DXVK/MoltenVK and optional user-supplied D3DMetal. Distinguish required, optional,
installed, incomplete and unavailable states. Each entry exposes version,
architectures, provenance/license, size when known, download/build state and
environments using it. Never invent a percentage when the transfer lacks a total.

Preserve verified resumable downloads and existing version/license gates. Keep
the known unavailable DXMT Latest channel clearly unavailable until a real release
and pin pass validation. Show Spock x86/x64 availability and the requested fallback
behavior. D3DMetal remains user supplied and retains existing sharing restrictions.
Sikarugir preference does not authorize relabeling another Wine build as Sikarugir
or introducing unverified engine binaries.

### Activity and troubleshooting

Show operation, target game/environment, start/end, state and result. A compact
status strip links active work to its Activity entry. Screens remain navigable
while mutations follow the actual executor's serialization rules.

Use stage progress where exact totals are unknown. Show human-readable failures
and the next safe action; expandable raw logs support diagnosis. Make Retry,
Reveal Folder, Continue Installation and Copy Diagnostic Report contextual.
Sanitize exported logs for secrets and personal paths without destroying the
local originals. Explain what the export contains before sharing it.

Do not infer that a game is running merely because a launch command returned
success. Distinguish command handoff, observed process state and unknown state.
Retain recovery across app restart for Terminal jobs and unfinished installations.

### Native Settings and first launch

Settings groups: General, Library Sources, Runtime Defaults, Appearance and
Advanced. Store Steam setup/account/library choices under Library Sources.
Keep per-game and per-environment overrides with their respective objects.
Respect current directory overrides and existing configuration paths.

First launch opens an empty Library with Install Windows Game and Add Installed
Game. Optional Connect Steam is secondary. Prerequisites appear when the chosen
task needs them; there is no global Steam/setup-complete gate for unrelated work.

## 5. Complete menu and command model

Use standard native macOS menu behavior. Do not add a duplicate Settings or
Dashboard menu. Preserve Edit and Window behavior and native text shortcuts.

| Menu | Contents |
| --- | --- |
| Cosmos | About, Settings…, Check for Updates…, standard app items |
| File | Add Game…, Add Installed EXE…, Import from Store submenu, New Environment…, Create/Update Mac App, standard Close |
| Edit | Native Undo/Redo where supported, Cut/Copy/Paste, Select All, Find |
| View | Library, Installations, Environments, Components, Activity; sidebar/inspector; grid/list; Refresh |
| Game | Play, game settings, locate/reveal files, file check, diagnosis, log, favorite, remove Library entry |
| Environment | Select associated environment, install program, clone, stop, dependencies/advanced tools, reset/delete |
| Window | Standard native window management |
| Help | Cosmos Help, Windows installation guide, SimCity guide, graphics guide, optional Steam guide, diagnostic report |

Store-specific actions such as Steam verification, detection and GOG sync belong
to File → Import from Store and the relevant source settings. Preset application,
compatibility lookup/reporting and recipe review belong to game troubleshooting
or environment dependencies. GPTK/OpenGL/Battle.net tools remain available under
the applicable environment's Advanced tools. Audit every existing notification,
button and context action before retiring its old entry point.

| Shortcut | Action |
| --- | --- |
| Command-N | Add Game |
| Command-O | Add Installed EXE |
| Command-Shift-N | New Environment |
| Command-1 through Command-5 | Five destinations in sidebar order |
| Command-Return | Play selected game |
| Command-F | Focus search in the current searchable destination |
| Command-R | Refresh current destination |
| Command-comma | Native Settings |
| Escape | Dismiss a dismissible sheet; does not silently terminate an installer |

Verify conflicts against native menu defaults before finalizing shortcuts.
Use ellipses for commands requiring more input. Destructive actions have explicit
target names, existing confirmations and no new default shortcut.

Toolbar buttons, menus, context menus and keyboard shortcuts all call the same
typed command with an explicit selected-object context. Availability is derived
from capabilities and prerequisites, not a blanket `isSteamReady` flag. Present
a reason and recovery path when an action cannot proceed. A missing selection
must never fall back to a different environment or last-selected Steam game.

## 6. Visual and interaction system

Use a restrained native macOS layout: compact sidebar, stable toolbar, readable
lists, optional inspector and purposeful game artwork. Retain Cosmos branding as
an accent. Remove oversized repeated hero sections, heavy gradients and nested
cards that crowd useful controls. Prefer system controls and system typography.

Define shared semantic colors, spacing, typography, focus states, status labels,
button hierarchy, sheets, lists, notices and empty/loading/error states. Support
light/dark, increased contrast, Reduce Transparency and Reduce Motion. Text and
icons accompany status colors. Long paths/titles wrap or expose a copyable full
value. Show ordinary language first, with technical detail where it informs a
decision; keep diagnostic internals out of the normal installation flow.

All critical tasks work with keyboard and VoiceOver. Keep focus stable after
refresh, errors and dismissals. Announce meaningful stage changes without reading
every log line. Provide visible alternatives to every context-menu action.
Use searchable/virtualized collections for large libraries and preserve selection
through refresh. Background file/process checks must not block the main thread.

## 7. Architecture and compatibility

Introduce these boundaries incrementally:

- **AppRouter**: typed destination, selection, back/forward and route restoration.
- **UnifiedGameLibraryStore**: read adapters over SavedProfile/Port/source records with
  stable source identities and per-item launch capabilities.
- **CommandRegistry**: shared action definitions, prerequisites and execution.
- **InstallationCoordinator**: persisted installation stages and continuation.
- **EnvironmentStore / ComponentStore**: observable summaries and contextual tools.
- **ActivityStore**: operation history and reconciliation with existing job tracking.
- Small destination views and shared components in place of expanding the large
  `ContentView` state/notification/scroll-anchor graph.

Do not merge records by title. Keep each underlying record's ID, launch semantics,
prefix, architecture and arguments. Reconcile duplicates by source identity and
verified target/environment; represent multiple launch choices explicitly when
they differ. Presentation adapters do not rewrite existing definitions on launch.

Retain existing `.conf` files, installation states, generated apps, named prefixes,
directory overrides, source provenance and compatible UserDefaults. Map old
navigation/preferences to the nearest new route. New UI-only state gets an
explicit schema/version and safe defaults. No prefix relocation or automatic
runtime upgrade is part of this redesign.

Initially keep serialized mutations where the runner requires them. Navigation,
search and read-only inspection remain available. Concurrent environment jobs
require a separate locking/ownership design and are not assumed by this plan.

## 8. Delivery sequence and exit gates

| Phase | Work | Required exit evidence |
| --- | --- | --- |
| 0. Inventory | Map every screen/action/notification to a destination and command; record before/after journeys and preserved data | Feature-parity checklist; no orphaned tools; existing tests green |
| 1. Interaction design | Wireframes and clickable prototype for first run, Library, wizard, environment and failures; visual tokens | Review at minimum/default widths, light/dark, realistic long titles and paths |
| 2. Foundation | Router, shared selection/commands, capability policies and service adapters | Menu/toolbar/context actions resolve identical targets; no new Steam gating |
| 3. Shell and Library | New sidebar/toolbar, unified Library, details, native Settings and menus | Existing games and Ports launch through their correct services; source data unchanged |
| 4. Installations | Wizard, destination preview, interactive handoff, resume/retry and registration | EXE/MSI, cancelled selection, restart and disconnected-drive journeys pass |
| 5. Environment and components | Contextual settings/files/dependencies, clone/reset/delete, runtime/graphics catalog | Existing architecture, Spock fallback, checksum and cleanup protections retained |
| 6. Activity and accessibility | Progress/history/recovery, log export, focus/keyboard/VoiceOver/appearance polish | No misleading success/cancel claims; interactive accessibility review recorded |
| 7. Removal and release | Remove obsolete navigation/state handlers, finish docs and screenshot coverage, preview testing | Full checks, feature parity, preview artifact and manual gates recorded against exact commit |

Use small PRs in that dependency order. Keep the current experience accessible
through a temporary development switch while the new Library/install flow reaches
parity; remove that switch and legacy shell only after validation. Do not maintain
two public navigation systems permanently. Migrate destinations before deleting
their original actions. No calendar estimate is committed until Phase 0/1 scope
and the native installer-handoff approach are verified.

## 9. Acceptance matrix

| Scenario | Pass condition |
| --- | --- |
| Unsupported host | Explain the actual platform requirement at launch/install; allow browsing/settings without implying Wine can run |
| Fresh install without Steam | Library, Add Game, Environments, Components and menus work; no forced Steam setup |
| SimCity EXE installation | Correct environment/folder and Windows path; explicit installed EXE; Library registration and later launch |
| Existing game | Add EXE without rerunning setup; preserve working directory, arguments and architecture |
| MSI installer | Validated MSI routing; no fake EXE treatment |
| Interrupted setup/selection | Restart resumes correct stage, title, folder and environment; no automatic setup rerun |
| Moved/external drive | Clear unavailable state; explicit locate/reconnect; original destination preserved |
| Multiple game sources | Every selection launches its own record; duplicate titles do not merge unrelated games |
| x86/WoW64 and Spock | Correct bitness/engine selection and x86 DLL/fallback messaging; real renderer/game tests recorded separately |
| Menus and context actions | Same target and availability as visible buttons; Steam independence; complete keyboard path |
| Environments | Clone before port registration; reset/delete protections and external-link preservation remain |
| Downloads | Resume/change/checksum failures stay recoverable; unavailable versions cannot imply installation success |
| Jobs and errors | App stays navigable; retries preserve input; Terminal work survives restart; unknown process state is labeled |
| Existing installation | Settings, prefixes, IDs and generated apps remain usable; no silent migration |
| Accessibility/layout | 960×640 and default window; light/dark; keyboard, VoiceOver, contrast and reduced-motion checks |
| Distribution | Debug/release builds, meaningful Swift/Python/shell tests, bundle/DMG audit and artifact verification |

Extend existing regression tests around changed contracts rather than rewriting
the backend test suite. Capture each destination and important wizard/error state.
Screenshots must be visually reviewed; successful image generation alone is not
an accessibility or layout pass. Test with empty, single-game, mixed-source and
large synthetic libraries without fabricating compatibility ratings.

Real SimCity installation, city creation, save/load and relaunch; real x86/WoW64
behavior; Spock renderer verification; and interactive accessibility remain manual
release gates. Public distribution also requires the existing signing/notarization
process. A preview build may ship earlier with those limits stated accurately.

## 10. First implementation slice

Start with Phase 0's action inventory and the Phase 1 prototype. The first working
vertical slice is **fresh launch → Library → Add Installed EXE → game details →
Play**, including matching File/Game menu actions and no Steam dependency.
Then add the installer/resume journey before replacing the environment/component
screens. This establishes the new selection and command model before the most
stateful workflows move onto it.
