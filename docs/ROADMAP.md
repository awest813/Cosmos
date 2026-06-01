# Cosmos Roadmap

**Cosmos** is a macOS game compatibility layer and launcher: it combines Wine, a
Metal-based D3D translation backend, per-game profiles, store integration
(Steam first), and one-click fixes so Windows games feel like normal Mac apps.

> The pitch is not "I rebuilt Wine." The pitch is **"Cosmos makes Windows games
> feel like Mac apps."** Cosmos starts by making existing tools easy, and only
> grows its own runtime once the layers underneath it are solid.

## Where we are today

This repository is at milestone **0.1 (Bootstrap)**. It ships a set of `.command`
bash scripts plus a shared Swift/`.app` launcher that downloads Wine (Gcenx
builds), creates a Steam Wine prefix, installs Steam, enables DXMT (or an opt-in
Apple GPTK / D3DMetal path), and generates per-game `.app` bundles from
`cosmos_configs/*.conf`.

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

### 0.1 — Bootstrap *(in progress)*
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
- [ ] macOS **app shell** UI (the SwiftUI dashboard is a stub, not yet wired to a build)
- [ ] First-class "Open logs" and "Reset bottle" actions in the UI
- **Success:** A user installs Cosmos and opens Windows Steam on macOS without Terminal.

### 0.2 — Game launchers
- Detect installed Steam games
- Generate `.app` launchers into `/Applications/Cosmos Games/`
- Per-game launch config (bottle path, Steam App ID / EXE path, backend, args, env)
- Game icons / artwork
- Dock / Launchpad support
- **Success:** A user can put a Windows Steam game in the Dock and launch it like a Mac app.

### 0.3 — Bottles & backends
- Bottle manager (Steam, GOG, Old Games, Test, …) — each with Wine version,
  Windows version, graphics backend, Retina mode, env vars, installed deps, logs,
  repair/reset
- Backend selector: `recommended | d3dmetal | dxmt | dxvk | wined3d`
- **Success:** A user can manage multiple isolated bottles and switch a game's backend from the UI.

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
