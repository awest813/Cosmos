# Developer README

This file documents implementation details for `run.command`, `uninstall.command`, and the Cosmos `.app` bundles.

## Source

Inspired by:
https://www.reddit.com/r/macgaming/comments/1r8vsnj/how_to_play_windows_steam_games_on_mac_with_m/

## What `run.command` Does

- Checks platform:
  - macOS only
  - Apple Silicon (`arm64`) only
- Ensures Rosetta 2 is available:
  - triggers `sudo` because Rosetta installation may be required
- Downloads and extracts Wine:
  - Wine builds are downloaded from Gcenx macOS Wine builds
  - default Wine version is controlled by `WINE_VERSION`
  - extracted into `WINE_ROOT` (defaults to `~/wine-$WINE_VERSION`)
- Initializes the Wine prefix:
  - default prefix location is `WINEPREFIX` (defaults to `~/.wine-steam-11`)
- Creates/updates a symlink next to the scripts pointing at `WINEPREFIX`:
  - name controlled by `WINEPREFIX_ALIAS_NAME` (defaults to `WINEPREFIX`)
- Steam installation:
  - downloads `SteamSetup.exe` into `STEAM_SETUP` (defaults to `/tmp/SteamSetup.exe`)
  - runs the installer via Wine
  - deletes `STEAM_SETUP` after Steam is detected in the prefix
- D3D translation backend (chosen by `GPTK_PATH`):
  - Default (DXMT):
    - downloads and installs into `DXMT_ROOT` (defaults to `~/DXMT`)
    - enables it via `WINEDLLPATH_PREPEND`
    - defaults `DXMT_LOG_LEVEL` to `error` unless already set by the caller
  - Opt-in (Apple Game Porting Toolkit / D3DMetal):
    - activated by setting `GPTK_PATH` to the GPTK root or directly to the folder containing its DLLs
    - common layouts are probed (`<path>`, `<path>/redist/lib/external`, `<path>/lib/external`, `<path>/lib`, `<path>/Libraries`)
    - copies the D3DMetal DLLs into `${WINEPREFIX}/drive_c/windows/system32/` and sets `WINEDLLOVERRIDES=d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n` (unless the caller already set `WINEDLLOVERRIDES`)
    - GPTK is **not** downloaded by this script -- Apple's EULA forbids redistribution, so you must obtain it from developer.apple.com yourself
    - a dedicated prefix (e.g. `WINEPREFIX=~/.wine-steam-gptk`) is recommended so GPTK and DXMT DLLs do not accumulate in the same prefix
- Launch mode:
  - Default (`COSMOS_DETACH=1`) runs Steam with `nohup ... & disown`, redirecting stdout/stderr to `${COSMOS_LAUNCH_LOG}` (defaults to `${TMPDIR:-/tmp}/cosmos-steam.log`). The Terminal window can be closed immediately after launch without killing Steam.
  - `COSMOS_DETACH=0` preserves the pre-patch foreground behavior (Terminal window must stay open).
  - The legacy `MERLOT_DETACH` / `MERLOT_LAUNCH_LOG` / `MERLOT_STEAM_LOG` names are still honored as fallbacks; the `COSMOS_*` names take precedence.
- App/dashboard actions:
  - `run.command --steam` launches Steam explicitly.
  - `run.command --profiles` opens `~/Library/Application Support/Cosmos/Profiles/` in Finder and exits (falling back to the legacy `~/Library/Application Support/Cider/Profiles/` if only that exists).
  - `run.command --game <path> [args...]` launches a saved profile executable directly.
  - `run.command --logs` opens the latest launch log (`COSMOS_LAUNCH_LOG`), or reveals its folder if no log exists yet, and exits.
  - `run.command --reset-bottle [--force]` deletes the Wine prefix (and its alias symlink) so the next launch recreates it and reinstalls Steam. Without `--force` it prompts for confirmation when run interactively, and refuses (rather than guessing) when stdin is not a TTY. Wine and DXMT downloads are preserved.
- Wine logging:
  - defaults `WINEDEBUG` to `-all,err+all` unless already set by the caller
- Writes registry values inside the prefix:
  - `HKCU\\Software\\Wine\\Mac Driver\\RetinaMode` controlled by `WINE_RETINA_MODE` (`0`/`1`)
  - Disables Windows mouse acceleration (Enhanced Pointer Precision):
    - `HKCU\\Control Panel\\Mouse\\MouseSpeed = 0`
    - `HKCU\\Control Panel\\Mouse\\MouseThreshold1 = 0`
    - `HKCU\\Control Panel\\Mouse\\MouseThreshold2 = 0`
  - Optional DirectInput override:
    - `HKCU\\Software\\Wine\\DirectInput\\MouseWarpOverride` controlled by `WINE_MOUSE_WARP_OVERRIDE` (`force|enable|disable|empty`)

## Configuration (Environment Variables)

Defaults are the values in `run.command`.

- `WINE_VERSION`
  - Wine build version to download (default: `11.8`)
  - Must exist as a `wine-devel-${WINE_VERSION}-osx64.tar.xz` asset in the [Gcenx macOS Wine builds](https://github.com/Gcenx/macOS_Wine_builds/releases). Gcenx prunes older releases periodically, so this default will need bumping over time.
- `DXMT_VERSION`
  - DXMT release version to download (default: `0.74`)
- `WINE_ROOT`
  - Where Wine is extracted (default: `~/wine-$WINE_VERSION`)
- `WINEPREFIX`
  - Where the Steam prefix lives (default: `~/.wine-steam-11`)
- `WINEPREFIX_ALIAS_NAME`
  - Name of the symlink created next to `run.command` (default: `WINEPREFIX`)
- `WINE_RETINA_MODE`
  - `1` enables, `0` disables (default: `0`)
- `WINE_MOUSE_WARP_OVERRIDE`
  - Empty keeps Wine default (and removes the key if it was set before)
  - Allowed values: `force`, `enable`, `disable`
- `GPTK_PATH`
  - Empty (default) uses DXMT. When set, switches the D3D backend to Apple's Game Porting Toolkit (D3DMetal) and skips the DXMT download.
  - Point at either the GPTK root directory or the folder containing its DLLs.
- `COSMOS_DETACH` (legacy alias: `MERLOT_DETACH`)
  - `1` (default) detaches Steam from the launching Terminal so the window can be closed without killing Steam.
  - `0` keeps the old foreground behavior.
- `COSMOS_LAUNCH_LOG` (legacy aliases: `MERLOT_LAUNCH_LOG`, `MERLOT_STEAM_LOG`, `COSMOS_STEAM_LOG`)
  - Path to the detached-mode launch log (default: `${TMPDIR:-/tmp}/cosmos-steam.log`).
- `COSMOS_SUPPORT_DIR`
  - Cosmos Application Support directory (default: `~/Library/Application Support/Cosmos`). `PROFILE_DIRECTORY` defaults to `${COSMOS_SUPPORT_DIR}/Profiles`.
- `COSMOS_MIN_MACOS_MAJOR`
  - Minimum macOS major version enforced at startup (default: `11`).
- `COSMOS_FORCE`
  - `1` skips the interactive confirmation for destructive actions such as `--reset-bottle`. The desktop app sets this after its own confirmation dialog. Default: `0`.
- `STEAM_GAME_ID`
  - When set (usually by a per-game `.conf`), Steam launches straight into that App ID via `-applaunch`.
- `STEAM_GAME_ARGS`
  - Extra arguments forwarded to the game (Steam passes anything after `-applaunch <id>`). Split on whitespace. Only used when `STEAM_GAME_ID` is set.

Example overrides (environment variables):

```bash
WINEPREFIX="$HOME/Games/SteamPrefix" WINE_RETINA_MODE=1 ./run.command
```

GPTK example (user-supplied Game Porting Toolkit, dedicated prefix):

```bash
WINEPREFIX="$HOME/.wine-steam-gptk" \
GPTK_PATH="$HOME/Apple-GPTK" \
./run.command
```

## What `uninstall.command` Removes

Targets derived from environment variables (defaults are the values in `uninstall.command`):

- `WINE_VERSION`
- `WINE_ROOT`
- `WINEPREFIX`
- `DXMT_ROOT`
- `STEAM_SETUP`
- `WINEPREFIX_ALIAS_NAME`

Additional hardcoded target:

- `/Applications/Cosmos Apps`

Notes:

- `uninstall.command` asks for confirmation per item and shows progress as `[X/N]`.
- `uninstall.command` uses `sudo` to remove `/Applications/Cosmos Apps`.
- `uninstall.command` does not remove Rosetta 2.
- Use the same `WINE_VERSION`/`WINE_ROOT`/`WINEPREFIX` values you used with `run.command` to uninstall the correct locations.

## Notes

- If Wine/DXMT/Steam are already present in the expected locations, `run.command` skips those steps.
- The scripts do not change macOS system settings (pointer acceleration, polling rate, etc.).
- `SCRIPT_DIR` can be overridden via environment variable. When run inside the `.app` bundle, the launcher sets it to the directory containing the `.app` so the `WINEPREFIX` alias symlink lands next to the app bundle inside `Cosmos Apps/`.
  - Alias creation is best-effort only. If `SCRIPT_DIR` is not writable (for example, `/Applications/Cosmos Apps` after a sudo install), `run.command` skips the symlink and continues.
- Tested on:
  - Apple M1 Max (32GB), macOS Sequoia 15.7.4
  - Apple M2 Pro (16GB), macOS Sequoia 15.7.4

## Cosmos Desktop App (app shell)

Milestone 0.1 includes a SwiftUI dashboard that wraps the shell flow so common
actions (launch Steam, launch a saved profile, open the profiles folder, open
logs, reset the bottle, install/uninstall) are available without Terminal.

### Sources

- `app/CosmosApp.swift` - `@main` entry point / window scene.
- `app/ContentView.swift` - the dashboard UI. It shells out to `run.command`,
  `install_cosmos.command`, and `uninstall.command`, resolving each script from
  the app bundle's `Resources/` first and falling back to the repository checkout
  during development.
- `Package.swift` - SwiftPM manifest. The app shell requires macOS 13+
  (`NavigationSplitView`); the shell scripts themselves still target macOS 11.

### Build

```bash
swift build -c release            # compile the Cosmos executable
scripts/build_cosmos_app.command  # build ./build/Cosmos.app (bundles the scripts)
INSTALL=1 scripts/build_cosmos_app.command  # also copy it into /Applications
```

`build_cosmos_app.command` compiles via SwiftPM, then assembles a
double-clickable `Cosmos.app` with `run.command`, `install_cosmos.command`,
`uninstall.command`, and `detect_steam_games.command` copied into
`Contents/Resources/` so the app is self-contained. Requires Xcode or the
Command Line Tools (`swift`).

## Auto-Detecting Steam Games

`detect_steam_games.command` scans the Steam libraries inside the Wine prefix and
turns each installed game into a launcher config, so you don't have to hand-write
a `.conf` per game.

How it works:

1. Finds Steam in the prefix (`Program Files (x86)/Steam` or `Program Files/Steam`).
2. Reads every library from `steamapps/libraryfolders.vdf`, mapping Windows paths
   to the filesystem through the prefix's `dosdevices/` drive symlinks.
3. Parses each `appmanifest_<appid>.acf` for the App ID and name.
4. Writes one generated config per game into `cosmos_configs/` named
   `steam-<appid>-<slug>.conf` (these carry an `AUTO-GENERATED` header and are
   git-ignored). Games that already have a hand-curated config with the same
   `STEAM_GAME_ID` are skipped so curated presets win.

Modes:

```bash
./detect_steam_games.command --list      # print detected games, write nothing
./detect_steam_games.command --write      # refresh generated configs (this is the default)
./detect_steam_games.command            # same as --write
./detect_steam_games.command --install   # refresh configs, then build all launchers
```

Re-running refreshes the generated set (stale configs for uninstalled games are
removed). After `--write`, run `./install_cosmos.command` to build the `.app`
launchers. The Cosmos dashboard's "Detect Games" button runs `--list`
(read-only) so it works even from the installed app.

### Per-game overrides

Because `--write` overwrites the generated `steam-*.conf` files, edits made to
them directly are lost on the next refresh. To attach **persistent** per-game
settings (graphics backend, extra env, launch args) to an auto-detected game,
drop a `cosmos_configs/overrides/<appid>.env` file with simple `KEY=VALUE` lines:

```sh
# cosmos_configs/overrides/250900.env
DXMT_CONFIG="d3d11.preferredMaxFrameRate=60;"
STEAM_GAME_ARGS="-windowed -novid"
# GPTK_PATH="/Users/you/GPTK"   # switch this game to the D3DMetal backend
```

On the next detect, those keys are merged into the generated launcher's
`RUN_ENV_NAMES` and assignments (and ride along into the built `.app`). Only
upper-snake-case keys are accepted, and `STEAM_GAME_ID` is reserved, so an
override file cannot inject arbitrary shell into the sourced config. Override
files are git-ignored; see `cosmos_configs/overrides/README.md`.

`run.command` forwards `STEAM_GAME_ARGS` to the game (anything after
`-applaunch <id>`), so launch arguments work for both curated and auto-detected
launchers.

### Per-game icons

During `--write`/`--install`, detection looks for the game's locally-cached Steam
artwork under `appcache/librarycache` (the square clienticon first, then the
portrait/landscape capsules, probing both the historical flat naming and the
newer per-appid subfolders). The first match is handed to
`scripts/make_app_icon.command`, which uses macOS `sips` + `iconutil` to
centre-crop it to square and assemble a multi-resolution `.icns` into
`cosmos_configs/icons/steam-<appid>.icns`. That path is written into the
generated config's `ICON_PATH`, so `install_cosmos.command` bakes it into the
`.app` bundle.

- Icons are cached and only rebuilt when the source artwork is newer; icons for
  uninstalled games are pruned so the cache mirrors the launcher set.
- A custom icon wins: set `ICON_PATH="…"` in the game's `overrides/<appid>.env`
  and it suppresses the auto-extracted one.
- On a fresh prefix Steam may not have downloaded library art yet, so some games
  fall back to the default Cosmos icon until art is cached. Set
  `COSMOS_SKIP_ICONS=1` to skip icon generation entirely.
- The icons directory is git-ignored.

## Cosmos App Bundles

`install_cosmos.command` assembles `Cosmos Apps/` in a temporary directory, then installs it into `/Applications/Cosmos Apps`.

### Structure

```
Cosmos Apps/
  <APP_NAME>.app/
    Contents/
      Info.plist               # App metadata (Spotlight, Finder, Dock)
      MacOS/
        CosmosLauncher         # Shared launcher for all generated apps
      Resources/
        cosmos.env             # Runtime env generated from cosmos_configs/*.conf
        run.command            # Copied from repo root at install time
        AppIcon.icns           # Icon for that app
```

### How it works

1. `install_cosmos.command` reads each `cosmos_configs/*.conf` file and generates one `.app` bundle per config inside `Cosmos Apps/` in a temporary directory.
2. It asks for `sudo`, replaces `/Applications/Cosmos Apps`, and copies the freshly generated folder there.
3. Each bundle uses the shared `app/cosmos/CosmosLauncher`, generated `Info.plist`, copied `run.command`, and an app-local `cosmos.env`.
4. `CosmosLauncher` opens Terminal and runs the embedded `run.command` with the environment overrides listed in that app's `cosmos.env`.
5. The launcher exports `SCRIPT_DIR` pointing to the directory containing the `.app`, so the shared `WINEPREFIX` alias symlink lands in `/Applications/Cosmos Apps/`.

### Install

```bash
./install_cosmos.command
```

To install only one config:

```bash
./install_cosmos.command binding-of-isaac
```

To create a new config, copy the template:

```bash
cp cosmos_configs/template.conf.example cosmos_configs/my-game.conf
```

### Source files

- `app/cosmos/CosmosLauncher` - shared launcher script for generated apps
- `app/cosmos/AppIcon.icns` - app icon
- `cosmos_configs/*.conf` - per-game launcher metadata and `run.command` environment overrides
- `cosmos_configs/template.conf.example` - starting point for new game configs; not built by the script
- `install_cosmos.command` - assembles and installs the `Cosmos Apps/` folder
