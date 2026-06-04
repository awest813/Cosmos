# Cosmos Roadmap

**Cosmos** is a macOS game compatibility layer and launcher: it combines Wine, a
Metal-based D3D translation backend, per-game profiles, store integration
(Steam first), and one-click fixes so Windows games feel like normal Mac apps.

> The pitch is not "I rebuilt Wine." The pitch is **"Cosmos makes Windows games
> feel like Mac apps."** Cosmos starts by making existing tools easy, and only
> grows its own runtime once the layers underneath it are solid.

## Where we are today

This repository has completed milestone **0.2 (Game launchers)**. It ships a set
of `.command` bash scripts plus a SwiftUI `.app` dashboard that downloads Wine
(Gcenx builds), creates a Steam Wine prefix, installs Steam, enables DXMT (or an
opt-in Apple GPTK / D3DMetal path), auto-detects installed Steam games, and
generates per-game `.app` bundles (with icons from Steam artwork) from
`cosmos_configs/*.conf`. The dashboard can detect and build those launchers in
one click, routing privileged steps through Terminal.

In Cosmos terms, the existing code already covers slices of the **Runtime**,
**Graphics**, **Profile**, and **Launcher** layers (see
[ARCHITECTURE.md](ARCHITECTURE.md)). The roadmap below describes how those slices
grow into a coherent product.

> **Heritage:** the codebase passed through earlier names (`Cider`, then
> `Merlot`) before Cosmos. The 0.1 rename keeps `MERLOT_*` env vars working as
> aliases and still cleans up the legacy `Merlot Apps` folder on uninstall, so
> existing installs keep working.

## Guiding principles

- **Make the boring path work first.** Steam launching reliably with zero Terminal
  use beats a half-built store/cloud/database.
- **Don't start with the custom runtime.** That is the swamp. Build the layers
  that make existing tools easy; ship a bundled runtime only at 1.0.
- **Backends are swappable tools, not religion.** D3DMetal, DXMT, DXVK/MoltenVK,
  and WineD3D are selectable per game. Normal users pick *Recommended*; nerds get
  the knobs. See [BACKENDS.md](BACKENDS.md).
- **Known-good defaults are the magic.** Like Proton, Cosmos's value is as much in
  curated per-game settings as in the runtime. See [PROFILE_FORMAT.md](PROFILE_FORMAT.md).
- **Respect licenses.** Bundle open-source pieces where licenses allow; let users
  point Cosmos at their own Apple GPTK install. Do **not** redistribute Apple
  proprietary D3DMetal files.

## Release milestones

The version line below is what gets pinned and tracked. Each release has a single
success criterion — if that sentence isn't true, the release isn't done.

### 0.1 — Bootstrap *(complete)*
- [x] **Rename Merlot → Cosmos** — scripts (`install_cosmos.command`,
  `app/cosmos/CosmosLauncher`, `cosmos_configs/`, `cosmos.env`), app bundle names
  (`Cosmos Apps`, `Steam (Cosmos).app`), bundle IDs (`com.cosmos.*`), and
  `COSMOS_*` env vars with `MERLOT_*` back-compat aliases
- [x] Apple Silicon / Intel detection + Rosetta check
- [x] macOS version check (`require_macos_version`, min major via `COSMOS_MIN_MACOS_MAJOR`)
- [x] Wine runtime download/selection (`WINE_VERSION`)
- [x] Default Steam bottle creation + Steam install + "Launch Steam"
- [x] Application Support path consolidated to `~/Library/Application Support/Cosmos/`
  (with fallback to the legacy `Cider/Profiles` location)
- [x] macOS **app shell** UI — SwiftUI dashboard (`app/CosmosApp.swift` +
  `app/ContentView.swift`) wired to a SwiftPM build (`Package.swift`) and a
  bundle-assembly script (`scripts/build_cosmos_app.command`)
- [x] First-class "Open logs" (`run.command --logs`) and "Reset bottle"
  (`run.command --reset-bottle`) actions, surfaced as UI buttons
- **Success:** A user installs Cosmos and opens Windows Steam on macOS without Terminal.

> Next: **0.3 — Bottles & backends**. The app shell shipped at 0.1 stays an
> evolving dashboard; polishing it (richer status, console mode) continues across
> later milestones.

### 0.2 — Game launchers *(complete)*
- [x] Detect installed Steam games — `detect_steam_games.command` scans the
  prefix's Steam libraries (`libraryfolders.vdf` + `appmanifest_*.acf`)
- [x] Generate `.app` launchers — detection emits `cosmos_configs/steam-*.conf`
  that `install_cosmos.command` builds into `/Applications/Cosmos Apps/`
- [x] Per-game launch config via Steam App ID (curated configs override auto ones)
- [x] Dock / Launchpad support (generated `.app` bundles, already supported)
- [x] "Detect Steam Games" surfaced in the dashboard (read-only list)
- [x] Game icons / artwork — `detect_steam_games.command` converts Steam's
  locally-cached art (`appcache/librarycache`) into per-game `.icns` via
  `scripts/make_app_icon.command` (sips + iconutil) and wires it into each
  generated launcher's `ICON_PATH`; falls back to the default icon when art or
  the macOS tools are unavailable
- [x] Richer per-game config in generated launchers (backend, env, args) —
  persistent per-game `cosmos_configs/overrides/<appid>.env` files are merged
  into the auto-generated launchers (and survive refresh), and `run.command`
  honors `STEAM_GAME_ARGS` to forward launch arguments to the game
- [x] One-click "detect → build" from the dashboard — the "Build Launchers"
  button runs `detect_steam_games.command --install` in Terminal.app (via
  `osascript`) so the build step's `sudo` prompt works; "Install Cosmos" and
  "Uninstall" route through Terminal the same way
- **Success:** A user can put a Windows Steam game in the Dock and launch it like a Mac app.

### 0.3 — Bottles & backends *(complete)*
- [x] Backend selector `recommended | dxmt | d3dmetal | dxvk | wined3d` —
  `run.command` validates `COSMOS_BACKEND` and resolves `recommended`
  (→ `d3dmetal` when `GPTK_PATH` is set, else `dxmt`, preserving prior behavior);
  dxmt/d3dmetal/wined3d work, dxvk is experimental (needs `DXVK_PATH` + MoltenVK).
  Settable per game via `.conf` / `overrides/<appid>.env`. See [BACKENDS.md](BACKENDS.md).
- [x] Bottle manager engine — `bottle.command` (list/create/info/set/path/launch/
  logs/reset/delete) manages named, isolated bottles under
  `~/Library/Application Support/Cosmos/Bottles/<name>/` (prefix + `bottle.conf` +
  logs). `run.command` honors `COSMOS_BOTTLE`, loading the bottle's prefix and
  settings (Wine version, backend, Retina, env) with precedence
  *explicit env > bottle.conf > defaults*. No bottle named → unchanged behavior.
- [x] UI: bottle manager + backend picker in the dashboard — the Bottles section
  lists bottles, creates them (name/backend/Windows/Retina sheet), switches a
  bottle's backend via a Picker, and launches/opens-logs/resets/deletes — all
  driven by `bottle.command`.
- **Success:** A user can manage multiple isolated bottles and switch a game's backend from the UI. ✅
- [ ] *(deferred)* Per-bottle Windows-version application — stored & shown today;
  applying it to the prefix registry is a follow-up.

### 0.4 — Profiles
- v0 profile schema (YAML/JSON) — see [PROFILE_FORMAT.md](PROFILE_FORMAT.md)
- Recommended backend + dependency recipes + local compatibility notes
- First 20 hand-tested game profiles
- **Success:** Cosmos automatically applies known-good settings for specific games.

### 0.5 — Repair engine
- Crash/log detection + missing-runtime detection
- One-click fixes (install VC++/DirectX redists, set Windows version, toggle
  Retina, change backend, kill stuck Wine processes, rebuild prefix, clear Steam
  shader/config caches, apply DLL overrides, controller mapping, force borderless)
- Bottle health check
- **Success:** When a game fails, Cosmos suggests useful fixes instead of dumping the user into logs.

### 0.6 — Store expansion
- Standalone EXE/MSI importer (Add Game → installer → create Cosmos game)
- GOG offline installers
- itch.io Windows games
- Epic via Legendary (experiment)
- **Success:** Users can add non-Steam Windows games and get the same launcher/profile experience.

### 0.7 — CosmosDB
- GitHub-hosted community compatibility database (see schema below)
- User reports, status badges, one-click profile updates
- **Success:** Cosmos has its own "ProtonDB for Mac" that feeds back into profiles.

### 1.0 — Cosmos Runtime
- Stable bundled Wine runtime (patched wine-mono/wine-gecko, DXMT + D3DMetal
  integration paths, DXVK/MoltenVK option, winetricks-style dependency system,
  default registry patches, controller fixes, game-specific patches)
- Profile-driven launching + backend switching + repair tools
- Steam + standalone games, 100+ compatibility profiles, clean docs
- Versioned like Proton: `Cosmos Experimental`, `Cosmos 1.0`, `Cosmos Legacy 32-bit`,
  `Cosmos DXMT`, `Cosmos D3DMetal`
- **Success:** Cosmos is useful to ordinary Mac gamers, not just its author.

### Later / optional — Console mode
- Fullscreen game grid, controller navigation, large cover art, Play button,
  compatibility badge, settings, repair, "Quit to Cosmos"
- Desktop mode = manage bottles/settings; Console mode = sit back and play.

## Build order (the version actually being followed)

> Steam launcher → `.app` game launcher → profiles → backend switcher →
> repair engine → compatibility database → custom runtime.

## CosmosDB report schema (preview)

Each report tracks: game, store, Mac model, chip, macOS version, Wine version,
backend, status, FPS range, fixes needed, notes.

Statuses: **Platinum** (works out of box) · **Gold** (small fixes) ·
**Silver** (playable with issues) · **Bronze** (launches but rough) ·
**Broken** (does not work) · **Blocked** (anti-cheat / DRM / AVX / etc.).

## Starter issues

- `[Core]` Create Cosmos app shell
- `[Core]` Create Application Support directory
- `[Core]` Detect Apple Silicon vs Intel Mac
- `[Core]` Check Rosetta status
- `[Wine]` Add Wine runtime selector
- `[Wine]` Create default Steam bottle
- `[Steam]` Download / install Steam
- `[Steam]` Launch Steam from Cosmos
- `[Logs]` Capture Wine output to log file
- `[Bottles]` Add reset bottle button
- `[Launcher]` Generate "Steam via Cosmos.app"
- `[Profiles]` Define v0 profile schema
- `[Profiles]` Load local YAML profiles
- `[Games]` Add Steam App ID launcher support
- `[Graphics]` Add backend enum: d3dmetal, dxmt, dxvk, wined3d
- `[Repair]` Add "kill Wine processes" action
- `[Docs]` Write manual Steam setup fallback

## Licensing note

Cosmos can integrate with Apple's Game Porting Toolkit but must be careful about
bundling Apple-owned components. Safer approach: bundle open-source pieces where
licenses allow, use Wine builds legally, let users point Cosmos at their own GPTK
install, and do not redistribute Apple proprietary files unless the license
clearly permits it.
</content>
</invoke>
