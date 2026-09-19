# Cosmos: premium experience plan

Reviewed September 7, 2026. Mission: make Windows games feel approachable on Mac through guided setup, sensible compatibility defaults, easy launching, and clear recovery.

## Reference patterns

- CrossOver: guided installation and explicit bottle management. Source: https://www.codeweavers.com/support/docs/crossover-mac/index
- Lutris: a unified game collection with configurable runners and installer recipes. Sources: https://lutris.net/faq and https://github.com/lutris/lutris/blob/master/docs/installers.rst
- Steam/Proton: compatibility tools integrated into the existing game launch flow, with per-game options when needed. Source: https://github.com/ValveSoftware/Proton

These are interaction references, not claims of equivalent Mac compatibility. Cosmos should keep its native macOS identity.

## Whole-app audit

| Area | Current gap | Priority / action |
| --- | --- | --- |
| Install / updates | Source-build and Terminal paths still burden new users; updates are detected but not a complete managed update experience. | P0 release work: signed/notarized distribution, upgrade/rollback fixtures, verified download integrity, clear release notes. Requires release credentials and packaging verification. |
| Startup / loading | Runtime status shells out synchronously; refresh loads profiles, recipes, and settings on the main thread. | P1 engineering: background snapshots, bounded subprocesses, stale-result protection and a visible initial loading state. Measure cold-start time before/after. |
| First-run setup | Guidance is improved, but helper launchers may be counted as games; external Terminal steps need clearer context. | P1: distinguish setup readiness from having a game, retain honest Terminal handoff, test empty and partial installations. |
| Library | Launch depends on double-click/context menus; favorite actions are hidden; technical sections compete with games. | Implement now: visible Play/Favorite actions, favorites filter, result count/reset, selected-game panel, technical sections collapsed by default. |
| Game identity | Repeated generic store icons make the library difficult to scan. | Implement now: distinct title-derived identity tiles. Follow-up: cached local/Steam artwork with async loading, licensing/source policy, bounded memory, and offline fallbacks. |
| Launch / status | Generic Running messages obscure the active operation; script success can sound like confirmed gameplay. | Implement now: named indeterminate task status, explicit terminal guidance, honest launch-handoff wording. Follow-up: track game processes before offering Stop or claiming Running. |
| Compatibility | Badges exist, but absence of evidence is easy to mistake for readiness. | Implement now: unknown status visible in the selected-game panel; preserve blocked-title warning flow. Follow-up: hardware/runtime-specific evidence, dates, confidence, and reproducible compatibility matrix. |
| Settings / bottles | Global and bottle-specific settings require care; advanced detail is plentiful. | Keep active environment explicit. Follow-up: per-game environment association, inheritance summary, reversible preset application, validated migrations. |
| Imports | File pickers and validation exist; store-specific installation complexity remains. | Follow-up: store capability labels, install-vs-import distinction, progress, duplicate resolution, and launch-after-import test fixtures. |
| Recovery | Parsed errors and suggested repair exist, but logs compete with ordinary use. | Implement now: retain repair navigation while collapsing technical sections; visible operation feedback. Follow-up: contextual retry and exportable support bundles with redaction. |
| Accessibility / visual quality | Prior pass fixed focus, contrast, and several combined controls; long labels/narrow windows still need live inspection. | Implement now: accessible independent actions and adaptive layouts. Release gate: keyboard-only, VoiceOver, Reduce Motion, light/dark, minimum window dimensions. |
| Architecture / tests | Large ContentView coordinates UI, processes and data. XCTest is unavailable in the current tools. | Extract new reusable experience components now. Follow-up: shared command coordinator, snapshot data layer, Xcode CI with UI fixtures; do not hide skipped tests. |

## Implementation pass in this task

1. Put the selected game, compatibility, active environment, Play, and Favorite together before secondary content.
2. Add explicit game actions and a favorites view with counts and one-click filter reset.
3. Give game tiles a consistent visual identity, preserve grid/list preferences, and keep selection available during jobs while launch remains guarded.
4. Collapse recommended presets, compatibility tools, repair, and game configuration details while preserving menu/deep-link behavior.
5. Show the operation name and truthful launch feedback; expose recent output on demand without inventing download percentages or game-running state.
6. Verify the release build, relevant behavioral checks, and inspect an isolated preview when the environment permits it.

## Completion criteria and next releases

This pass is complete when changes above compile, existing launch-path safeguards remain intact, filters recover from empty results, and the result is reviewable. It is not a signed release or a claim that every Windows game works.

Next release gates: actual first-run installation on Intel and Apple Silicon; minimum-window and assistive checks; launch/exit/relaunch for Steam, direct executable, and GOG fixtures; supported/blocked/unknown compatibility cases; interruption/failure/retry of downloads and imports; update/rollback on existing data. Record evidence per gate before calling the product release-ready.


## Delivered and verified in this pass

Implemented the six items above: selected-game Play panel; independent Play/Favorite controls; favorites filtering, counts and reset; title identity tiles; collapsed game tools and idle logs; named progress and honest launch-handoff wording. Also aligned default environment inspection with an explicit WINEPREFIX override so the UI and launcher use the same configured path.

Verification: release compilation; isolated native preview with four sample games, including a long title and unknown compatibility. Confirmed Favorites narrows 4 games to 1, an unmatched search produces a recoverable empty state, Show All Games resets search and favorites, list mode renders separate Play/Favorite actions, and accessibility exposes those actions individually. Final source checks include the clear-search label correction and collapsed log view.

Not verified: actual Windows game startup, minimum-width/light-mode screenshots, VoiceOver speech output, settings deep-link scrolling after this layout change, and relaunch persistence in the final binary. Full XCTest remains blocked by the installed tools. Distribution, asynchronous startup, process tracking, richer artwork, and the other next-release items above remain planned rather than shipped.
