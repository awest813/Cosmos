# Cosmos

**Play Windows Steam games on Mac — with one-click launchers, curated profiles, and a graphical dashboard.**

Cosmos is a macOS game compatibility layer: it downloads Wine, sets up a Steam bottle, translates DirectX via Metal (DXMT by default), detects your library, and builds Dock-friendly `.app` launchers. No Terminal required for the happy path.

| | |
|---|---|
| **Platform** | Apple Silicon (M1–M4) and Intel Macs (x86_64) |
| **macOS** | 11+ for scripts · **13+** for the desktop app (15 Sequoia tested) |
| **Status** | Milestone **0.7.1** — **105** curated profiles, repair engine, CosmosDB, Intel + Apple Silicon, parsed error recovery; Phases A–E of [user gaps plan](docs/PLAN.md) complete |
| **Developers** | See [README_DEV.md](README_DEV.md) for scripts, env vars, and architecture |

> **Upgrading from Merlot?** Your Wine prefix and saved profiles are reused. `MERLOT_*` environment variables still work; `uninstall.command` also removes the legacy `Merlot Apps` folder.

---

## Table of contents

- [Features](#features)
- [Quick start](#quick-start)
- [The dashboard](#the-dashboard)
- [Other ways to run Cosmos](#other-ways-to-run-cosmos)
- [Graphics backends](#graphics-backends)
- [Bottles](#bottles)
- [Profiles, repair & compatibility](#profiles-repair--compatibility)
- [Non-Steam games](#non-steam-games)
- [Troubleshooting](#troubleshooting)
- [System requirements & storage](#system-requirements--storage)
- [Uninstall](#uninstall)
- [Documentation](#documentation)
- [Credits](#credits)

---

## Features

- **Guided first-time setup** — install Wine, create a Steam prefix, install Steam, build game launchers
- **SwiftUI dashboard** — launch Steam, manage bottles, apply profiles, run repairs, import non-Steam games
- **Per-game `.app` launchers** — Spotlight/Dock friendly apps in `/Applications/Cosmos Apps`
- **Curated YAML profiles** — known-good backends, dependencies, and fixes for popular titles
- **Repair engine** — diagnose logs, install winetricks deps, one-click fixes
- **CosmosDB** — compatibility hints from ProtonDB, AppleGamingWiki, MacGamingDB, and community reports
- **Multiple graphics backends** — DXMT (default), Apple GPTK/D3DMetal, DXVK, WineD3D
- **Isolated bottles** — separate Wine prefixes with independent settings
- **Store import** — standalone EXE/MSI, GOG, itch.io, Battle.net, Epic (via Legendary)

---

## Quick start

### Option A — Prebuilt app (when available)

Check [GitHub Releases](https://github.com/awest813/Cosmos/releases) for a signed **`Cosmos.dmg`**. When a release is published, download it, open the disk image, and drag **Cosmos** to **Applications** — then skip to [first-time setup](#3-run-first-time-setup-1015-minutes) below.

Unsigned preview builds can be produced locally with `scripts/build_dmg.command` (see Option B).

### Option B — Build from source

#### 1. Get the source

```bash
git clone https://github.com/awest813/Cosmos.git
cd Cosmos
```

Or download the repository as a ZIP from GitHub and unzip it.

#### 2. Build the desktop app

```bash
scripts/build_cosmos_app.command
```

This compiles the SwiftUI dashboard and installs **`Cosmos.app`** to `/Applications`. macOS may prompt for Xcode Command Line Tools or your password.

**Sharing a build?** Produce a drag-to-Applications disk image:

```bash
scripts/build_dmg.command
# → build/Cosmos.dmg
```

On first launch of an unsigned build: right-click **Cosmos** → **Open** → confirm.

### 3. Run first-time setup (~10–15 minutes)

1. Open **Cosmos** from `/Applications` or Spotlight.
2. Follow the in-app checklist — one button per step:
   - **Install Cosmos** — helper launchers into `/Applications/Cosmos Apps`
   - **Prepare Steam bottle** — Wine + prefix + graphics backend
   - **Install Steam** — unattended install (wizard fallback if needed)
   - **Build game launchers** — detect games and create `.app` bundles
3. When Terminal opens for a step, complete any prompts there, then press **Refresh** (⌘R) in Cosmos.

Detailed manual path: [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md).

### 4. Play

- Launch **Steam (Cosmos).app** from `/Applications/Cosmos Apps`, or use **Quick Launch** in the dashboard.
- Install a Windows game in Steam.
- Run **Build Game Launchers** — your games appear in the sidebar and as Dock apps.
- Double-click a game launcher (e.g. **Binding of Isaac (Cosmos).app**).

After Steam starts, you can close Terminal — Steam runs detached by default (`COSMOS_DETACH=1`).

---

## The dashboard

Cosmos.app is a single-window launcher with a sidebar (saved games) and a main panel organized into sections (**⌘1–4** to switch once Steam is ready):

| Section | What you can do |
|---------|-----------------|
| **Launch** | Quick Launch (Steam + selected profile), Steam Wine settings (backend, Windows version, Retina) |
| **Games** | Curated YAML profiles, compatibility lookup & reports, repair & dependencies |
| **Tools** | Maintenance (detect, build/sync launchers, logs, reset), non-Steam game import |
| **Bottles** | Create isolated prefixes, switch backends, launch Steam per bottle |

**Sidebar** — search saved games; **Favorites** (star a title) and **Recent** sections; filter chips (All / Favorites / Recent) for large libraries. New Steam installs surface in the status summary with a one-tap sync. Context menu to launch, reveal config, or copy executable path.

**Output panel** — live log for embedded commands; copy/clear; banners with parsed errors and **Apply Suggested** / **Diagnose** shortcuts on launch failure.

**Launch** — saved profiles launch via direct `.exe` path or Steam `applaunch` when only a Steam App ID is configured.

Privileged steps (install Cosmos, prepare bottle, uninstall) open **Terminal.app** when they need `sudo` or interactive prompts. **Build Launchers** and **Sync Steam Library** run in the embedded console when possible (`~/Applications/Cosmos Apps`); Terminal is offered if install fails.

---

## Other ways to run Cosmos

### Launcher-only (no desktop app)

```bash
./install_cosmos.command          # Build .app launchers → /Applications/Cosmos Apps
./detect_steam_games.command --install   # Detect games + rebuild launchers
```

If macOS blocks a script: right-click → **Open** → confirm.

### Terminal-first (generic Steam)

```bash
./run.command                     # Set up if needed, launch Steam
./run.command --setup-steam       # Prepare prefix without launching
./run.command --status            # Setup checklist / doctor
./run.command --logs              # Open latest launch log
./run.command --sync-steam        # Build launchers for newly installed games only
./run.command --game "<path>"     # Launch a saved profile executable
```

### Common scripts

| Script | Purpose |
|--------|---------|
| `run.command` | Wine prefix, Steam install, game launch |
| `bottle.command` | Isolated bottles (create, set, launch, reset) |
| `detect_steam_games.command` | Scan Steam library; `--install` (full) or `--sync` (incremental) |
| `install_cosmos.command` | Install `/Applications/Cosmos Apps` bundles |
| `profile.command` | Apply curated YAML game profiles |
| `repair.command` | Diagnose logs, install deps, apply fixes |
| `import_game.command` | Add non-Steam games (GOG, itch, Battle.net, Epic) |
| `cosmosdb.command` | Compatibility lookup, sync, local reports |
| `uninstall.command` | Remove Cosmos apps, prefixes, runtimes (interactive) |

Full flags, environment variables, and internals: **[README_DEV.md](README_DEV.md)**.

---

## Graphics backends

Cosmos translates DirectX to Metal. Pick a backend per bottle or via environment variables.

| Backend | Best for | Notes |
|---------|----------|-------|
| **DXMT** (default) | Most games | Fast, open-source; downloaded automatically |
| **D3DMetal** | Select titles | Requires your own [Apple Game Porting Toolkit](https://developer.apple.com/download/all/) install — **not redistributed** |
| **DXVK** | Testing | Experimental; needs `DXVK_PATH` + MoltenVK |
| **WineD3D** | Compatibility | Software D3D; slower but forgiving |
| **recommended** | Convenience | D3DMetal if `GPTK_PATH` is set, else DXMT |

```bash
# Examples
COSMOS_BACKEND=dxmt ./run.command
GPTK_PATH="$HOME/GPTK" COSMOS_BACKEND=d3dmetal ./run.command --setup-steam
./bottle.command create retro --backend wined3d --windows win7
```

Deep comparison and troubleshooting: [docs/BACKENDS.md](docs/BACKENDS.md).

---

## Bottles

A **bottle** is a named, isolated Wine prefix under `~/Library/Application Support/Cosmos/Bottles/`. Use bottles when you want different backends, Windows versions, or game libraries without mixing prefixes.

**In the app:** open the **Bottles** section (⌘4), create a bottle, select it — the toolbar shows the active bottle; repair/detect commands target it via `COSMOS_BOTTLE`.

**On the command line:**

```bash
./bottle.command create gaming --backend dxmt --windows win10
./bottle.command launch gaming --steam
./bottle.command set gaming COSMOS_BACKEND d3dmetal
./bottle.command list
```

---

## Profiles, repair & compatibility

### Curated profiles

Hand-tested YAML recipes live in `profiles/` (Steam, GOG, itch, Battle.net, standalone). They declare recommended backends, winetricks dependencies, fixes, and notes.

```bash
./profile.command list
./profile.command apply profiles/steam/steam-250900-binding-of-isaac.yaml
```

During detection, Cosmos auto-exports `cosmos_configs/overrides/<appid>.env` from a matching profile when you haven't written your own override.

Schema: [docs/PROFILE_FORMAT.md](docs/PROFILE_FORMAT.md).

### Repair

When a game fails, use the **Games** section or:

```bash
./repair.command diagnose
./repair.command apply-suggested
./repair.command install-dep vcrun2015
```

Recipes: `recipes/dependencies/` and `recipes/fixes/`.

### CosmosDB

Look up compatibility, sync the community database, and save local macOS play reports:

```bash
./cosmosdb.command lookup 250900
./cosmosdb.command sync
./cosmosdb.command report 250900 gold "Stable on M2, DXMT"
```

Statuses: **Platinum · Gold · Silver · Playable · Bronze · Broken · Blocked**. Details: [docs/COSMOSDB.md](docs/COSMOSDB.md).

---

## Non-Steam games

Import standalone Windows games from the dashboard **Tools** section or via `import_game.command`:

| Source | Command / UI action |
|--------|---------------------|
| EXE / MSI installer | Run Installer |
| Already-installed EXE | Register EXE |
| GOG offline setup | GOG Installer |
| itch.io download | itch.io Folder |
| Battle.net | Install Battle.net client → Add Blizzard Game |
| Epic (Legendary) | Epic Login → Add Epic Game (`brew install legendary-gl`) |

After importing, run **Install Cosmos** or `install_cosmos.command` to build the `.app` launcher.

Guide: [docs/STORE_IMPORT.md](docs/STORE_IMPORT.md).

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Steam won't start | Dashboard → **Open Logs**, or `~/Library/Application Support/Cosmos/logs/steam-launch.log`. Manual setup: [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md) |
| Game crashes | Failure banner may offer **Apply Suggested**; or **Tools → Games → Diagnose Logs** |
| Command shows “exit 1” | Scroll the output panel — Cosmos surfaces `Error:` lines from scripts when present |
| Setup stuck after Terminal | Click **Refresh** (⌘R) or run `./run.command --status` |
| macOS blocks scripts/app | Right-click → **Open** → confirm (unsigned dev build) |
| Rosetta prompt | Allow — Cosmos needs Rosetta 2 on Apple Silicon |
| Empty game list | Install a Windows game in Steam, then **Build Game Launchers** |
| Wrong prefix used | Select the correct bottle in the dashboard, or set `COSMOS_BOTTLE=name` |

```bash
./run.command --status          # Read-only setup summary
./run.command --compat-check 220   # Curated compatibility for a Steam App ID
```

More: [docs/BACKENDS.md](docs/BACKENDS.md) · [README_DEV.md](README_DEV.md)

---

## System requirements & storage

**Supported**

- Apple Silicon Mac (M-series) or Intel Mac (x86_64)
- macOS 11+ (scripts) · macOS 13+ (desktop app)
- Rosetta 2 on Apple Silicon only (installed automatically if missing; not required on Intel)

**Tested:** M1 Max / M2 Pro, macOS Sequoia 15.7.4 · Intel paths are supported but less frequently exercised in CI

**Rough disk usage**

| Component | Typical size | Location |
|-----------|--------------|----------|
| Wine build | ~2 GB | `~/wine-<version>` |
| DXMT | ~500 MB | `~/DXMT` |
| Steam + games | 100 GB+ | Inside the Wine prefix |
| Bottles & logs | Varies | `~/Library/Application Support/Cosmos/` |

First launch is slow (downloads). Later launches use the cache.

---

## Uninstall

1. Exit Steam cleanly (**Steam → Exit**).
2. Run `./uninstall.command` (or use the dashboard **Uninstall** button — opens Terminal).
3. Confirm each item when prompted (`y` / `n`).

Removes `/Applications/Cosmos Apps`, Wine prefixes, and downloaded runtimes. Does not remove Rosetta 2.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [README_DEV.md](README_DEV.md) | Script internals, env vars, CI, app architecture |
| [docs/PLAN.md](docs/PLAN.md) | User gaps and prioritized product plan |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones and what's next |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layered design (UI, profile, runtime, graphics, launcher) |
| [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md) | Manual Steam / prefix setup |
| [docs/BACKENDS.md](docs/BACKENDS.md) | Graphics backend comparison |
| [docs/PROFILE_FORMAT.md](docs/PROFILE_FORMAT.md) | YAML profile schema |
| [docs/COSMOSDB.md](docs/COSMOSDB.md) | Compatibility database & reports |
| [docs/STORE_IMPORT.md](docs/STORE_IMPORT.md) | Non-Steam import workflows |
| [docs/LICENSING.md](docs/LICENSING.md) | Third-party licenses (Wine, DXMT, winetricks, GPTK) |
| [docs/LGPL_IMPACT.md](docs/LGPL_IMPACT.md) | Practical LGPL impact (Wine, DXMT channels, offline bundles) |

---

## Credits

Cosmos builds on the macOS Wine ecosystem and community knowledge:

- Inspired by [this r/macgaming guide](https://www.reddit.com/r/macgaming/comments/1r8vsnj/how_to_play_windows_steam_games_on_mac_with_m/) and discussed in [this thread](https://www.reddit.com/r/macgaming/comments/1rflhp8/oneclick_solution_to_run_windows_games_on_apple/)
- Wine builds: [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- DXMT and other integrated open-source projects — see [docs/OPEN_SOURCE_INTEGRATIONS.md](docs/OPEN_SOURCE_INTEGRATIONS.md)

**License notes:** Cosmos (MIT) downloads **LGPL Wine** and may use **LGPL DXMT** on the Latest channel (`COSMOS_ALLOW_LGPL=1` by default; Pinned DXMT 0.80 is MIT). Offline bundles include `runtime/NOTICE.md` and source offers. See [docs/LGPL_IMPACT.md](docs/LGPL_IMPACT.md). GPTK/D3DMetal is not redistributed — obtain it from [developer.apple.com](https://developer.apple.com/download/all/).
