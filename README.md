# Run Windows Steam games on Apple Silicon Mac (Wine + Graphics Backend + Profiles)

For developer details, see the [Developer README](README_DEV.md).

> **Cosmos** is a macOS game compatibility layer and launcher for Apple Silicon Macs.
> It sets up Wine, optionally uses D3D translation layers (DXMT, Apple Game Porting
> Toolkit, DXVK), manages isolated Wine prefixes ("bottles"), auto-detects installed
> Steam games, and generates Spotlight-friendly `.app` launchers with per-game presets.
>
> Milestones **0.4 (Profiles)** through **0.6 (Store expansion)** are complete,
> including Epic import via Legendary. See [docs/ROADMAP.md](docs/ROADMAP.md).
> See [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
>
> **Upgrading from the old "Merlot" builds?** Your existing Wine prefix and saved
> profiles are reused. The `MERLOT_*` environment variables still work as
> aliases, and `uninstall.command` also removes the legacy `Merlot Apps` folder.

## References & Credits

- Inspired by this Reddit post:
  [How to play Windows Steam games on Mac with M...](https://www.reddit.com/r/macgaming/comments/1r8vsnj/how_to_play_windows_steam_games_on_mac_with_m/)
- Wine builds used by this project:
  [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- Reddit post about this project:
  [One-click solution to run Windows games on Apple...](https://www.reddit.com/r/macgaming/comments/1rflhp8/oneclick_solution_to_run_windows_games_on_apple/)

## Download

1. Click the green button `Code`, then `Download ZIP`.
2. Unzip the downloaded ZIP file (double-click it).

## Install

### Quick Start: Desktop App (Recommended)

The easiest way to use Cosmos is the desktop app, which handles installation,
game detection, bottle management, and graphics backend selection through a
graphical interface.

#### Build and Install the Desktop App

1. In Finder, locate the unzipped folder.
2. Open Terminal and run:
   ```bash
   cd /path/to/Cosmos
   scripts/build_cosmos_app.command
   ```
   This builds and installs `Cosmos.app` into `/Applications`.
3. If macOS prompts you, follow the instructions (may ask for your password or
   to install Xcode Command Line Tools).

#### Launch Cosmos App

1. Open `Cosmos.app` from `/Applications`, or find it in Spotlight as "Cosmos".
2. Use the app to:
   - **First-time setup** — guided checklist with one button per step
   - **Prepare Bottle** — download Wine, create the prefix, and install Steam (no launch)
   - **Launch Steam** — start Steam in a default Wine environment
   - **Detect Games** — auto-detect installed Steam games and build launchers
   - **Manage Bottles** — create isolated Wine prefixes with different backends
   - **Add Non-Steam Games** — import EXE/MSI installers, GOG setups, or itch.io downloads
   - **View Profiles** — open your saved game profiles in Finder
   - **View Logs** — check launch logs for troubleshooting
   - **Install/Uninstall** — manage the `/Applications/Cosmos Apps` launchers

### Alternative 1: Simple Launchers (Without Desktop App)

If you prefer not to use the desktop app, you can generate Spotlight-friendly
launchers directly.

#### Install:

1. In Finder, locate the unzipped folder.
2. Double-click `install_cosmos.command`.
3. If macOS blocks it, right-click `install_cosmos.command` -> `Open` -> confirm `Open`.
4. It installs `Cosmos Apps` into `/Applications`.

#### Run:

1. Open one of the apps in `/Applications/Cosmos Apps`, or find it in Spotlight:
   - `Steam (Cosmos).app` to launch Steam without game-specific presets.
   - A game launcher, for example `Binding of Isaac (Cosmos).app`, to use settings optimized for that game.
2. If macOS blocks it, right-click the app → `Open` → confirm `Open`.
3. After Steam launches, the Terminal window can be closed (Steam continues running).
   (This is the default behavior; set `COSMOS_DETACH=0` if you prefer keeping Terminal open.)

`Cosmos Apps` includes `Steam (Cosmos).app` plus ready-made launchers for supported
games. Each game launcher includes presets optimized for that game.

**Optional:** To add your own game config, create a file in `cosmos_configs/` and run
`install_cosmos.command` again. See the [Developer README](README_DEV.md) for details.

### Alternative 2: Generic Steam Launcher (Terminal)

If you want the general Steam-in-Wine setup without creating game-specific launchers:

1. In Finder, locate the unzipped folder.
2. Double-click `run.command`.
3. If macOS blocks it, right-click `run.command` → `Open` → confirm `Open`.
4. After Steam launches, the Terminal window can be closed.

Or, from Terminal with custom options:

```bash
WINEPREFIX="$HOME/Games/SteamPrefix" WINE_RETINA_MODE=1 ./run.command
```

See the [Developer README](README_DEV.md) for all configuration options.

## Graphics Backends

Cosmos supports multiple D3D translation backends for running DirectX 9, 10, 11, and 12 games:

- **DXMT** (default) — fast, open-source Metal translation. Works well for most games.
- **D3DMetal** (Apple Game Porting Toolkit) — requires a user-supplied GPTK install from `developer.apple.com`.
- **DXVK** (experimental) — Vulkan-to-Metal via MoltenVK; slower but useful for testing.
- **WineD3D** — Wine's software D3D implementation; most compatible but slower.

Select a backend when creating a bottle or set it per-game:

```bash
# Use the desktop app to manage bottles and backends, or:
./bottle.command create mybot --backend d3dmetal --gptk-path "$HOME/GPTK"
```

See [docs/BACKENDS.md](docs/BACKENDS.md) for detailed backend comparison and troubleshooting.

## Bottles (Isolated Wine Prefixes)

A **bottle** is a named, isolated Wine prefix with its own settings. Bottles let you
keep, say, a `steam` bottle on DXMT and a `retro` bottle on WineD3D without their
prefixes colliding.

**Using the desktop app:** Click "Manage Bottles" to create, configure, and launch bottles.

**Using the command line:**

```bash
./bottle.command create mybot --wine 11.8 --windows win10 --backend dxmt --retina 0
./bottle.command launch mybot                    # Launch Steam in this bottle
./bottle.command launch mybot --game "…/Game.exe" # Launch a specific game
./bottle.command set mybot COSMOS_BACKEND d3dmetal  # Change backend
./bottle.command reset mybot                    # Delete prefix, keep settings
```

See the [Developer README](README_DEV.md) for full bottle documentation.

## What to Expect

### First Launch

- You may be asked for your macOS password to install Rosetta (if missing).
- The first launch downloads Wine, graphics backend DLLs, and Steam (takes a few minutes).
- Steam should open inside Wine.

### Subsequent Launches

- Launches are faster (downloads are cached).
- Each bottle maintains its own Wine prefix and installed games.
- Games launch with optimized settings for your chosen backend and game profile.

## Stop

To close Steam cleanly:

1. In Steam, use the menu: `Steam` → `Exit`.
2. Wait until Steam fully closes.
3. You can close Terminal at any time; with the default `COSMOS_DETACH=1` behavior, Steam is detached from it.

## Uninstall

If Steam is running, follow the steps in "Stop" first.

1. Double-click `uninstall.command`.
2. If macOS blocks it, right-click `uninstall.command` -> `Open` -> confirm `Open`.
3. It may ask for your macOS password to remove `/Applications/Cosmos Apps`.
4. It will ask for confirmation for each item it wants to remove. Type `y` to remove it, or `n` to skip it (if you want to keep something).

## System Requirements & Notes

### Supported Systems

- **Apple Silicon Macs only** (M1, M2, M3, etc.). Intel Macs are not supported.
- **macOS 11 (Big Sur) or later** for the core shell scripts.
- **macOS 13 (Ventura) or later** for the Cosmos desktop app (macOS 15.7.4 Sequoia officially tested and recommended).
- **Rosetta 2** — installed automatically if missing.

### Tested Configurations

- Apple M1 Max (32GB), macOS Sequoia 15.7.4
- Apple M2 Pro (16GB), macOS Sequoia 15.7.4

### Performance & Compatibility

- **First launch** is slow (downloads Wine, backend DLLs, and Steam). Subsequent launches are fast (cached).
- **Game compatibility** depends on the graphics backend and game:
  - DXMT works well for most games and is the default (fast, open-source).
  - D3DMetal (Apple Game Porting Toolkit) may work better for certain titles but requires manual setup.
  - WineD3D is most compatible but slower (software D3D).
- **Multiple prefixes/bottles** isolate game installations and configurations; they do not affect macOS system performance.

### Storage

The default installation uses roughly:

- Wine build: ~2 GB (installed to `~/wine-*` where `*` is the version, e.g., `~/wine-11.8`)
- DXMT: ~500 MB (installed to `~/DXMT`)
- Steam and games: depends on your library (usually 100 GB+, in the Wine prefix)
- Cosmos files and bottles: `~/Library/Application Support/Cosmos/Bottles/` (per-bottle prefixes and logs)

## Troubleshooting

**Steam won't launch?** Check the launch log in the Cosmos app (click "View Logs") or see `~/Library/Application Support/Cosmos/logs/steam-launch.log`. Full manual steps: [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md).

**Game crashes?** Try switching graphics backends via the Bottles section or the command line.

**Need more help?** See [docs/BACKENDS.md](docs/BACKENDS.md) and [README_DEV.md](README_DEV.md) for advanced configuration.

## What The Scripts Do

### Main Scripts

**`run.command`**
- Installs Rosetta 2 (if missing; requires `sudo`).
- Downloads Wine (Gcenx macOS Wine builds) and sets up a Steam Wine prefix (or a named bottle).
- Downloads and installs Steam into that prefix.
- Enables a graphics backend (DXMT by default, or another choice).
- Launches Steam with optimized settings.

**`bottle.command`**
- Creates, manages, and launches isolated Wine prefixes ("bottles").
- Each bottle can use different Windows versions, backends, and per-game settings.
- Loads bottle-specific settings (e.g., `COSMOS_BACKEND`, `GPTK_PATH`) with priority over defaults.

**`detect_steam_games.command`**
- Scans Steam libraries inside a Wine prefix.
- Auto-generates per-game launcher configs with optimized settings.
- Builds per-game `.app` icons from Steam artwork (cached in `cosmos_configs/icons/`).

**`install_cosmos.command`**
- Assembles Spotlight-friendly `.app` bundles for Steam and each detected game.
- Installs the bundle folder to `/Applications/Cosmos Apps`.
- Each app bundles its config and environment for consistent launches.

**`scripts/build_cosmos_app.command`**
- Builds the Cosmos desktop app (SwiftUI dashboard) into `Cosmos.app`.
- Bundles all helper scripts and configs into the app for portability.
- Optional `INSTALL=1` copies it to `/Applications`.

**`uninstall.command`**
- Removes files/directories created by the scripts (with per-item confirmation).
- Asks for `sudo` to remove `/Applications/Cosmos Apps`.
- Does not remove Rosetta 2 or Wine DLLs (can be reused by other projects).

### Desktop App (Cosmos.app)

- Graphical interface to common operations: Prepare Bottle, Launch Steam, Detect Games, Manage Bottles, View Logs, Profiles, Install/Uninstall. Manual setup: [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md).
- Automatically discovers and launches embedded scripts from the app bundle.
- Bottles section shows all created bottles with their current settings.
