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

#### Or: Build a Drag-to-Applications Installer (`Cosmos.dmg`)

To produce a single double-clickable disk image (handy for sharing a build):

```bash
cd /path/to/Cosmos
scripts/build_dmg.command
```

This builds the app and packages `build/Cosmos.dmg`. Open it and drag **Cosmos**
into **Applications** — no compiling needed on the receiving Mac. On first launch
of an unsigned build, right-click `Cosmos` → `Open` → confirm `Open`.

#### Launch Cosmos App

1. Open `Cosmos.app` from `/Applications`, or find it in Spotlight as "Cosmos".
2. Use the app to:
   - **First-time setup** — guided checklist with one button per step
   - **Prepare Bottle** — download Wine, create the prefix, and install Steam (no launch)
   - **Launch Steam** — start Steam in a default Wine environment
   - **Detect Games** — auto-detect installed Steam games and build launchers
   - **Manage Bottles** — create isolated Wine prefixes with different backends
   - **Add Non-Steam Games** — import EXE/MSI installers, GOG setups, itch.io downloads, or Battle.net games
   - **View Profiles** — open your saved game profiles in Finder
   - **View Logs** — check launch logs for troubleshooting
   - **Install/Uninstall** — manage the `/Applications/Cosmos Apps` launchers

### Alternative 1: Simple Launchers (Without Desktop App)

If you prefer not to use the desktop app, you can generate Spotlight-friendly
launchers directly.

#### Install:

```bash
# Build .app launchers and install to /Applications/Cosmos Apps
./install_cosmos.command

# If macOS blocks it, right-click and select "Open"
```

#### Run:

```bash
# Find launchers in /Applications/Cosmos Apps or Spotlight:
# - Steam (Cosmos).app           # Launch Steam without game presets
# - Binding of Isaac (Cosmos).app # Game-specific launcher with optimized presets
# - (and other detected games)

# If macOS blocks launching, right-click → "Open" → confirm
# After Steam launches, the Terminal window can be closed (Steam continues running)
# (This is the default behavior; set COSMOS_DETACH=0 to keep Terminal open)

# Or use command line to rebuild launchers:
WINEPREFIX="$HOME/Games/MyPrefix" ./detect_steam_games.command --install
```

`Cosmos Apps` includes `Steam (Cosmos).app` plus ready-made launchers for supported
games. Each game launcher includes presets optimized for that game.

**Optional:** To add your own game config, create a file in `cosmos_configs/` and run:

```bash
./install_cosmos.command
```

See the [Developer README](README_DEV.md) for details on creating custom game configs.

### Alternative 2: Generic Steam Launcher (Terminal)

If you want the general Steam-in-Wine setup without creating game-specific launchers:

```bash
# Navigate to the Cosmos folder and run
cd /path/to/Cosmos
./run.command

# Or set custom environment variables and run
WINEPREFIX="$HOME/Games/SteamPrefix" WINE_RETINA_MODE=1 ./run.command

# Or just prepare Steam without launching
./run.command --setup-steam

# Check setup status
./run.command --status

# View logs
./run.command --logs
```

After Steam launches, the Terminal window can be closed (by default `COSMOS_DETACH=1` runs Steam detached).

See [Command Reference → run.command](#runcommand) and [Environment Variables](#environment-variables) for all options.

## Graphics Backends

Cosmos supports multiple D3D translation backends for running DirectX 9, 10, 11, and 12 games:

- **DXMT** (default) — fast, open-source Metal translation. Works well for most games.
- **D3DMetal** (Apple Game Porting Toolkit) — requires a user-supplied GPTK install from `developer.apple.com`.
- **DXVK** (experimental) — Vulkan-to-Metal via MoltenVK; slower but useful for testing.
- **WineD3D** — Wine's software D3D implementation; most compatible but slower.

Select a backend when creating a bottle, or set it per-game via environment variables or `.conf` files:

```bash
# Use the default backend (DXMT)
./run.command

# Specify DXMT explicitly
COSMOS_BACKEND=dxmt ./run.command

# Use Apple Game Porting Toolkit (must provide path to GPTK)
GPTK_PATH="$HOME/GPTK" COSMOS_BACKEND=d3dmetal ./run.command --setup-steam

# Use WineD3D (software, more compatible but slower)
COSMOS_BACKEND=wined3d ./run.command

# Use experimental DXVK backend
DXVK_PATH="$HOME/custom-dxvk" COSMOS_BACKEND=dxvk ./run.command

# Create a bottle with a specific backend
./bottle.command create gaming --backend d3dmetal --gptk-path "$HOME/GPTK"
./bottle.command create retro --backend wined3d

# Switch a bottle's backend
./bottle.command set gaming COSMOS_BACKEND dxvk

# Use 'recommended' to auto-select the best backend
# (d3dmetal if GPTK_PATH is set, else dxmt)
COSMOS_BACKEND=recommended ./run.command
```

See [docs/BACKENDS.md](docs/BACKENDS.md) for detailed backend comparison and troubleshooting.

## Bottles (Isolated Wine Prefixes)

A **bottle** is a named, isolated Wine prefix with its own settings. Bottles let you
keep, say, a `steam` bottle on DXMT and a `retro` bottle on WineD3D without their
prefixes colliding. Each bottle has independent Wine versions, Windows versions, graphics backends, and per-game settings.

**Using the desktop app:** Click "Manage Bottles" to create, configure, and launch bottles.

**Using the command line:** See [Command Reference → bottle.command](#bottlecommand) for all options.

**Common workflows:**

```bash
# Create and launch a bottle
./bottle.command create mybot
./bottle.command launch mybot                   # Launches Steam in mybot

# Create a bottle for older games with WineD3D (more compatible but slower)
./bottle.command create retro --backend wined3d --windows win98
./bottle.command launch retro

# Create a bottle using Apple Game Porting Toolkit
./bottle.command create gptk --backend d3dmetal --gptk-path "$HOME/GPTK"
./bottle.command launch gptk --game "./MyGame.exe"

# Modify a bottle's settings
./bottle.command set mybot WINDOWS_VERSION win10
./bottle.command set mybot COSMOS_BACKEND d3dmetal

# View bottle info
./bottle.command info mybot

# Delete a bottle (loses all games/data in that prefix)
./bottle.command delete mybot --force
```

See the [Developer README](README_DEV.md) for additional bottle documentation.

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

## Environment Variables

Configure Cosmos behavior by setting environment variables before running commands. All variables are optional with sensible defaults.

### Core Paths & Versions

```bash
# Wine build version to download (default: 11.8)
# Must exist in https://github.com/Gcenx/macOS_Wine_builds/releases
WINE_VERSION=11.8 ./run.command

# Where Wine is extracted (default: ~/wine-$WINE_VERSION)
WINE_ROOT="$HOME/custom-wine" ./run.command

# Wine prefix location (default: ~/.wine-steam-11)
WINEPREFIX="$HOME/Games/MyPrefix" ./run.command

# Name of the symlink created next to run.command (default: WINEPREFIX)
WINEPREFIX_ALIAS_NAME="MyPrefix" ./run.command

# Directory for generated configs and icons (default: cosmos_configs/)
COSMOS_CONFIGS_DIR="$HOME/Library/Application Support/Cosmos/cosmos_configs" ./run.command

# Directory for bottles (default: ~/Library/Application Support/Cosmos/Bottles)
COSMOS_BOTTLES_DIR="$HOME/custom-bottles" ./run.command

# Log directory (default: ~/Library/Application Support/Cosmos/logs)
COSMOS_SUPPORT_DIR="$HOME/custom-cosmos" ./run.command
```

### Graphics Backends

```bash
# Graphics backend selector (default: recommended)
# Options: recommended | dxmt | d3dmetal | dxvk | wined3d
# 'recommended' uses d3dmetal if GPTK_PATH is set, else dxmt
COSMOS_BACKEND=d3dmetal ./run.command

# DXMT backend version to download (default: 0.74)
DXMT_VERSION=0.75 ./run.command --setup-steam

# DXMT install location (default: ~/DXMT)
DXMT_ROOT="$HOME/custom-dxmt" ./run.command

# DXMT log level (default: error)
# Options: error | warning | info | debug
DXMT_LOG_LEVEL=debug ./run.command

# Apple Game Porting Toolkit path (enables d3dmetal backend)
# Point at GPTK root or folder containing its DLLs
GPTK_PATH="$HOME/GPTK" ./run.command

# DXVK DLLs folder path (enables experimental dxvk backend)
DXVK_PATH="$HOME/custom-dxvk" ./run.command
```

### Windows & Display Settings

```bash
# Windows version reported inside the prefix (default: none)
# Options: winxp | win7 | win8 | win10 | win11
WINDOWS_VERSION=win10 ./run.command

# Enable/disable Wine's Retina mode (default: 0)
# Set to 1 for high-DPI displays
WINE_RETINA_MODE=1 ./run.command

# Mouse warp override behavior (default: Wine's default)
# Options: force | enable | disable | (empty to remove)
WINE_MOUSE_WARP_OVERRIDE=force ./run.command
```

### Wine & Debug Settings

```bash
# Wine debug output (default: -all,err+all)
# See Wine documentation for full syntax
WINEDEBUG="-all,+relay" ./run.command

# Wine CPU to emulate (rarely needed)
WINEARCH=win32 ./run.command

# Additional Wine DLL path (prepended to system)
WINEDLLPATH_PREPEND="$HOME/custom-dlls" ./run.command

# Wine DLL overrides (e.g., force native or builtin)
WINEDLLOVERRIDES="mscoree=n,b" ./run.command

# Enable verbose startup logging
COSMOS_DEBUG=1 ./run.command --status
```

### Bottle & Launch Mode

```bash
# Use a specific bottle for all commands
COSMOS_BOTTLE=mybot ./run.command

# Detach Steam from Terminal (default: 1)
# Set to 1 to close Terminal without killing Steam
# Set to 0 to keep Terminal open while Steam runs
COSMOS_DETACH=1 ./run.command

# Silent Steam install mode (default: 1)
# Set to 1 for unattended install via NSIS /S flag
# Set to 0 to show the SteamSetup.exe wizard
COSMOS_STEAM_SILENT=1 ./run.command --setup-steam

# Steam log location (default: ~/Library/Application Support/Cosmos/logs/steam-launch.log)
COSMOS_LAUNCH_LOG="$HOME/steam.log" ./run.command

# Force certain operations (e.g., --reset-bottle without prompting)
COSMOS_FORCE=1 ./run.command --reset-bottle
```

### Legacy Compatibility (Merlot → Cosmos)

For backward compatibility with old "Merlot" scripts, these environment variables are honored as fallbacks:

```bash
# Legacy name for COSMOS_BOTTLE
MERLOT_BOTTLE=mybot ./run.command

# Legacy name for COSMOS_DETACH
MERLOT_DETACH=0 ./run.command

# Legacy name for COSMOS_LAUNCH_LOG
MERLOT_LAUNCH_LOG="$HOME/steam.log" ./run.command

# Legacy name for COSMOS_STEAM_LOG
MERLOT_STEAM_LOG="$HOME/steam-install.log" ./run.command
```

The `COSMOS_*` names always take precedence over their `MERLOT_*` equivalents if both are set.

See [README_DEV.md](README_DEV.md#configuration-environment-variables) for complete documentation.

## Command Reference

### run.command

The main launcher script. Manages Wine prefixes, downloads and installs Steam, and launches games.

```bash
Usage: run.command [ACTION]

Actions:
  (none) | --steam        Set up the bottle if needed and launch Steam (default).
  --setup-steam           Prepare Wine, DXMT/backend, and Steam (no launch).
  --install-steam         Install or reinstall Steam in an existing prefix only.
  --status                Show setup progress and the next step, then exit.
  --compat-check <appid>  Print the curated compatibility status for a Steam App ID
                          (warns if broken/blocked), then exit.
  --game <path> [args...] Launch a saved profile executable directly.
  --run-installer <file>  Run a Windows .exe/.msi installer in the prefix.
  --profiles              Open the saved profiles folder in Finder and exit.
  --logs                  Open the latest launch log and exit.
  --reset-bottle [--force] Delete the Wine prefix so it is recreated next launch.
  --help | -h             Show this usage information.
```

**Examples:**

```bash
# Launch Steam (default behavior, no args needed)
./run.command

# Prepare Wine and Steam without launching
WINEPREFIX="$HOME/Games/SteamPrefix" ./run.command --setup-steam

# Launch a specific game via saved profile
./run.command --game "$HOME/Library/Application Support/Cosmos/Profiles/my-game.exe"

# Install a game from a Windows installer
./run.command --run-installer "./MyGame-Setup.exe"

# Check setup status
./run.command --status

# Check if a game is known to work (Ctrl+F for AppID on https://steamdb.info)
./run.command --compat-check 220

# View the latest launch log
./run.command --logs

# Delete the Wine prefix and let it rebuild on next launch
./run.command --reset-bottle

# Use custom environment variables
WINE_RETINA_MODE=1 WINDOWS_VERSION=win10 ./run.command

# Use a specific Wine version
WINE_VERSION=11.7 ./run.command --setup-steam
```

### bottle.command

Manage isolated Wine prefixes with different configurations (bottling).

```bash
Usage: bottle.command <command> [args]

Commands:
  list                          List all bottles and a one-line summary.
  create <name> [options]       Create a bottle (prefix is built on first launch).
      --wine <version>          Pin a Wine version (e.g. 11.8).
      --windows <ver>           winxp | win7 | win8 | win10 | win11.
      --backend <backend>       recommended | dxmt | d3dmetal | dxvk | wined3d.
      --retina <0|1>            Enable/disable Wine RetinaMode.
  info <name>                   Show a bottle's settings and status.
  set <name> <KEY> <VALUE>      Set/replace a setting (e.g. COSMOS_BACKEND dxmt).
  path <name>                   Print the bottle's prefix path.
  launch <name> [run args...]   Launch into the bottle (runs run.command).
  logs <name>                   Show the bottle's latest launch log.
  reset <name> [--force]        Delete the prefix only (keep settings/logs).
  delete <name> [--force]       Delete the whole bottle.

Known settings: WINE_VERSION, WINDOWS_VERSION, COSMOS_BACKEND, WINE_RETINA_MODE,
COSMOS_DETACH, GPTK_PATH, DXVK_PATH, plus any UPPER_SNAKE_CASE env var run.command honors.
```

**Examples:**

```bash
# List all bottles
./bottle.command list

# Create a bottle with default settings
./bottle.command create mybot

# Create a bottle for retro games with WineD3D
./bottle.command create retro --backend wined3d --windows win98

# Create a bottle using Apple Game Porting Toolkit (requires GPTK install)
./bottle.command create gptk-games --backend d3dmetal --gptk-path "$HOME/GPTK"

# Create a bottle with a specific Wine version
./bottle.command create wine117 --wine 11.7 --windows win10

# Get info about a bottle
./bottle.command info mybot

# Launch Steam in a bottle
./bottle.command launch mybot

# Launch a specific game in a bottle
./bottle.command launch mybot --game "./Binding\ of\ Isaac.exe"

# Change a bottle's backend
./bottle.command set mybot COSMOS_BACKEND d3dmetal

# View a bottle's launch log
./bottle.command logs mybot

# Delete a bottle's Wine prefix (recreates on next launch)
./bottle.command reset mybot

# Completely delete a bottle
./bottle.command delete mybot
```

### detect_steam_games.command

Scan for installed Steam games and auto-generate launcher configs.

```bash
Usage:
  detect_steam_games.command            # default: refresh generated configs
  detect_steam_games.command --list     # print detected games, write nothing
  detect_steam_games.command --write    # write/refresh generated configs (default)
  detect_steam_games.command --install  # write configs, then build all launchers
  detect_steam_games.command --verify   # list games + verify installdir on disk
```

**Examples:**

```bash
# Detect and list installed Steam games
./detect_steam_games.command --list

# Generate launcher configs for detected games
./detect_steam_games.command --write

# Generate configs and build all .app launchers
./detect_steam_games.command --install

# Verify game directories exist on disk
./detect_steam_games.command --verify

# Use a specific Wine prefix
WINEPREFIX="$HOME/Games/MyPrefix" ./detect_steam_games.command --list
```

### install_cosmos.command

Build and install Spotlight-friendly .app launchers.

```bash
# Build .app bundles and install to /Applications/Cosmos Apps
./install_cosmos.command

# Also uninstall previous installations first
UNINSTALL_FIRST=1 ./install_cosmos.command
```

### build_cosmos_app.command & build_dmg.command

Build the desktop app.

```bash
# Build the Cosmos.app desktop application
./scripts/build_cosmos_app.command

# Build and install to /Applications
INSTALL=1 ./scripts/build_cosmos_app.command

# Build a redistributable .dmg disk image
./scripts/build_dmg.command

# Repackage an already-built Cosmos.app into a .dmg
SKIP_BUILD=1 ./scripts/build_dmg.command
```

### uninstall.command

Remove Cosmos-created files and folders.

```bash
# Interactively remove /Applications/Cosmos Apps, Wine prefixes, and backend DLLs
./uninstall.command

# Force removal without confirmation (use with caution)
# (set via confirmation prompts, not command-line flag)
```

## What The Scripts Do

**`run.command`** — Main launcher that manages Wine, downloads Steam, installs backends, and launches games. See [Command Reference](#runcommand) for all flags.

**`bottle.command`** — Creates and manages isolated Wine prefixes ("bottles") with independent settings and backends. Each bottle can have different Windows versions, graphics backends, and game-specific presets. See [Command Reference](#bottlecommand).

**`detect_steam_games.command`** — Scans Steam libraries inside a Wine prefix, auto-generates per-game launcher configs with optimized settings, and builds per-game `.app` icons from Steam artwork (cached in `cosmos_configs/icons/`). See [Command Reference](#detect_steam_gamescommand).

**`install_cosmos.command`** — Assembles Spotlight-friendly `.app` bundles for Steam and each detected game, then installs them to `/Applications/Cosmos Apps`. Each app bundles its config and environment for consistent launches.

**`scripts/build_cosmos_app.command`** — Builds the Cosmos desktop app (SwiftUI dashboard) into `Cosmos.app`, bundles all helper scripts and configs, and optionally installs to `/Applications`. See [Command Reference](#build_cosmos_appcommand--build_dmgcommand).

**`scripts/build_dmg.command`** — Builds the Cosmos desktop app and packages it as a drag-to-Applications `build/Cosmos.dmg` for easy redistribution.

**`uninstall.command`** — Removes files/directories created by Cosmos with per-item confirmation. Does not remove Rosetta 2 or Wine DLLs (can be reused).

### Desktop App (Cosmos.app)

- Graphical interface to common operations: Prepare Bottle, Launch Steam, Detect Games, Manage Bottles, View Logs, Profiles, Install/Uninstall. Manual setup: [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md).
- Automatically discovers and launches embedded scripts from the app bundle.
- Bottles section shows all created bottles with their current settings.
