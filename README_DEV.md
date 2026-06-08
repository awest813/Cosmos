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
  - Default (`COSMOS_DETACH=1`) runs Steam with `nohup ... & disown`, redirecting stdout/stderr to `${COSMOS_LAUNCH_LOG}` (default: `~/Library/Application Support/Cosmos/logs/steam-launch.log`). The Terminal window can be closed immediately after launch without killing Steam.
  - `COSMOS_DETACH=0` preserves the pre-patch foreground behavior (Terminal window must stay open).
  - The legacy `MERLOT_DETACH` / `MERLOT_LAUNCH_LOG` / `MERLOT_STEAM_LOG` names are still honored as fallbacks; the `COSMOS_*` names take precedence.
- App/dashboard actions:
  - `run.command --steam` launches Steam explicitly.
  - `setup.command` — guided first-time setup in Terminal (install + `--setup-steam`)
  - `run.command --setup-steam` prepares Wine, the prefix, backend DLLs, and Steam without launching (see [docs/STEAM_SETUP.md](docs/STEAM_SETUP.md)).
  - `run.command --install-steam` installs or reinstalls Steam in an existing prefix only (skips Wine/backend downloads). Cleans up incomplete Steam folders before retrying; validates the downloaded `SteamSetup.exe`.
  - `run.command --profiles` opens `~/Library/Application Support/Cosmos/Profiles/` in Finder and exits (falling back to the legacy `~/Library/Application Support/Cider/Profiles/` if only that exists).
  - `run.command --game <path> [args...]` launches a saved profile executable directly.
  - `run.command --status` (alias `--doctor`) prints a read-only setup summary — Wine download, prefix, Steam install, and saved profile count — plus the recommended next command, then exits. It never modifies the prefix and mirrors the dashboard's setup checklist.
  - `run.command --logs` opens the latest launch log (`COSMOS_LAUNCH_LOG`), or reveals its folder if no log exists yet, and exits.
  - `run.command --reset-bottle [--force]` deletes the Wine prefix (and its alias symlink) so the next launch recreates it and reinstalls Steam. Without `--force` it prompts for confirmation when run interactively, and refuses (rather than guessing) when stdin is not a TTY. Wine and DXMT downloads are preserved.
- Wine logging:
  - defaults `WINEDEBUG` to `-all,err+all` unless already set by the caller
- Writes registry values inside the prefix:
  - `HKCU\\Software\\Wine\\Mac Driver\\RetinaMode` controlled by `WINE_RETINA_MODE` (`0`/`1`)
  - `HKCU\\Software\\Wine\\Version` controlled by `WINDOWS_VERSION` (`winxp|win7|win8|win10|win11`; empty removes the override and restores Wine's default)
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
- `WINDOWS_VERSION`
  - Reported Windows version inside the prefix: `winxp|win7|win8|win10|win11`. Empty (default) keeps Wine's default and removes any prior override. Usually set per bottle via `bottle.conf`.
- `WINE_MOUSE_WARP_OVERRIDE`
  - Empty keeps Wine default (and removes the key if it was set before)
  - Allowed values: `force`, `enable`, `disable`
- `COSMOS_BACKEND`
  - Graphics backend selector: `recommended` (default) | `dxmt` | `d3dmetal` | `dxvk` | `wined3d`. See [docs/BACKENDS.md](docs/BACKENDS.md).
  - `recommended` resolves to `d3dmetal` if `GPTK_PATH` is set, else `dxmt`. Settable per game via a `.conf` or `overrides/<appid>.env`.
- `GPTK_PATH`
  - Path to a user-supplied Game Porting Toolkit install, used by the `d3dmetal` backend (and by `recommended` when set). Point at the GPTK root or the folder containing its DLLs. Cosmos never downloads GPTK (Apple EULA).
- `DXVK_PATH`
  - Path to a folder of DXVK DLLs (`d3d11.dll`, `dxgi.dll`, …), used by the experimental `dxvk` backend. DXVK on macOS needs MoltenVK.
- `COSMOS_DETACH` (legacy alias: `MERLOT_DETACH`)
  - `1` (default) detaches Steam from the launching Terminal so the window can be closed without killing Steam.
  - `0` keeps the old foreground behavior.
- `COSMOS_STEAM_SILENT`
  - `1` (default) installs Steam unattended via the NSIS `/S` flag — no wizard clicks. Cosmos polls for `steam.exe` (up to ~2 min) and, since a silent install can auto-start Steam, stops the prefix afterward so the explicit launch step is clean. Falls back to the interactive wizard if the silent run does not produce `steam.exe`.
  - `0` always shows the graphical `SteamSetup.exe` wizard.
- `STEAM_LAUNCH_ARGS`
  - Extra flags passed to `steam.exe` on launch (default: `-no-cef-sandbox -cef-single-process -noverifyfiles`). Adapted from MIT [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine). Set empty to disable.
- `COSMOS_STEAM_WEBHELPER_WRAPPER`
  - `1` (default) builds/installs the vendored MIT `steamwebhelper.exe` wrapper when `mingw-w64` is available (`brew install mingw-w64`).
- `COSMOS_STEAM_SEED_FONTS` / `COSMOS_STEAM_CA_BUNDLE`
  - `1` (default) copy macOS CJK fonts + CA bundle into the prefix during setup.
- `COSMOS_STEAM_WINEDLLOVERRIDES`
  - DLL overrides merged at Steam launch (default disables Steam overlay DLLs, sets DXMT-friendly `n,b` chain). Set empty to skip.
- `WINE_VIRTUAL_DESKTOP` / `WINE_VIRTUAL_DESKTOP_NAME`
  - Optional Wine virtual desktop wrapper (`auto`, `WxH`, or empty to disable). See [docs/OPEN_SOURCE_INTEGRATIONS.md](docs/OPEN_SOURCE_INTEGRATIONS.md).
- `COSMOS_LAUNCH_LOG` (legacy aliases: `MERLOT_LAUNCH_LOG`, `MERLOT_STEAM_LOG`, `COSMOS_STEAM_LOG`)
  - Path to the detached-mode launch log (default: `~/Library/Application Support/Cosmos/logs/steam-launch.log`).
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
- `COSMOS_BOTTLE`
  - Name of a bottle to launch into (see [Bottles](#bottles)). Its prefix and `bottle.conf` settings are loaded with precedence *explicit env > bottle.conf > defaults*. Unset = the legacy single-prefix behavior.

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

## Bottles

A **bottle** is a named, isolated Wine prefix plus its settings, managed by
`bottle.command`. Bottles let you keep, say, a `steam` bottle on DXMT and a
`oldgames` bottle on WineD3D without their prefixes (or DLLs) colliding.

Layout — `~/Library/Application Support/Cosmos/Bottles/<name>/`:

```
<name>/
  bottle.conf   # KEY="value" settings, loaded by run.command as defaults
  prefix/       # the WINEPREFIX (created on first launch)
  logs/         # per-bottle launch logs
```

CLI:

```bash
./bottle.command create steam --wine 11.8 --windows win10 --backend dxmt --retina 0
./bottle.command list
./bottle.command set steam COSMOS_BACKEND d3dmetal     # any UPPER_SNAKE_CASE env
./bottle.command set steam GPTK_PATH "$HOME/GPTK"
./bottle.command info steam
./bottle.command launch steam                          # runs run.command in the bottle
./bottle.command launch steam --game "drive_c/.../Game.exe"
./bottle.command logs steam
./bottle.command reset steam   [--force]               # delete the prefix, keep settings
./bottle.command delete steam  [--force]               # delete the whole bottle
```

`run.command` activates a bottle when `COSMOS_BOTTLE=<name>` is set (this is what
`bottle.command launch` does). It loads the bottle's `prefix` as `WINEPREFIX`,
points the launch log at the bottle's `logs/`, and applies `bottle.conf` settings
(`WINE_VERSION`, `COSMOS_BACKEND`, `WINE_RETINA_MODE`, `GPTK_PATH`, …) with
precedence **explicit env > bottle.conf > built-in defaults**. With no
`COSMOS_BOTTLE`, behavior is exactly as before (the `~/.wine-steam-11` prefix).
Persistent settings for that default prefix live in
`~/Library/Application Support/Cosmos/steam.conf` (same `KEY="value"` format as
`bottle.conf`) and can be edited from the dashboard's **Steam Wine Settings**
section or by hand. Precedence: **explicit env > steam.conf > built-in defaults**.
On first launch, Cosmos seeds `steam.conf` with recommended defaults (including
`COSMOS_LAUNCH_LOG` under `~/Library/Application Support/Cosmos/logs/steam-launch.log`).
Invalid values in `steam.conf` are clamped on launch so a typo cannot brick Steam.

Known settings validated on `create`/`set`: `WINDOWS_VERSION`
(`winxp|win7|win8|win10|win11`), `COSMOS_BACKEND`
(`recommended|dxmt|d3dmetal|dxvk|wined3d`), `WINE_RETINA_MODE` (`0|1`). Any other
`UPPER_SNAKE_CASE` key is stored as a plain env default. `WINEPREFIX` and
`COSMOS_BOTTLE` are reserved (Cosmos manages them). `WINDOWS_VERSION` is applied
to the prefix on launch via `HKCU\Software\Wine\Version`.

To auto-detect games inside a bottle, point detection at its prefix:

```bash
WINEPREFIX="$(./bottle.command path steam)" ./detect_steam_games.command --list
```

## Integration tooling (0.4–0.7 preview)

See [docs/OPEN_SOURCE_INTEGRATIONS.md](docs/OPEN_SOURCE_INTEGRATIONS.md) and
[docs/LICENSING.md](docs/LICENSING.md).

| Script | Purpose |
| --- | --- |
| `detect_steam_games.command --verify` | List games + verify `installdir` on disk |
| `scripts/verify_steam_detection.command` | Standalone detection cross-check |
| `scripts/test_steam_detection.sh` | Fixture-based unit tests (CI) |
| `repair.command` | Winetricks deps + fix recipes (`recipes/`) |
| `profile.command` | Apply YAML profiles → overrides + repair |
| `cosmosdb.command` | ProtonDB lookup (hint) + local macOS reports |

```bash
./detect_steam_games.command --verify
./repair.command install-dep vcrun2015
./profile.command apply profiles/steam/steam-250900-binding-of-isaac.yaml
./cosmosdb.command lookup 250900
./cosmosdb.command report 250900 gold "DXMT, win10, stable on M2"
```

## Cosmos Desktop App (app shell)

A SwiftUI dashboard wraps the shell flow so common actions (launch Steam, launch
a saved profile, detect and build game launchers, open the profiles folder, open
logs, reset the bottle, install/uninstall) are available from one window.

### Sources

- `app/CosmosApp.swift` - `@main` entry point / window scene.
- `app/ContentView.swift` - the dashboard UI. It shells out to `run.command`,
  `install_cosmos.command`, `uninstall.command`, `detect_steam_games.command`,
  and `bottle.command`, resolving each script from the app bundle's `Resources/`
  first and falling back to the repository checkout during development.
- `app/Bottle.swift` - the `Bottle` model and `BottleStore` (reads the bottles
  directory + `bottle.conf` for the dashboard's Bottles section).
- `app/GameProfile.swift` / `app/Recipe.swift` / `app/CosmosPaths.swift` -
  curated YAML profiles and repair recipes for the dashboard UI.
- `app/CosmosLogoView.swift` - the drawn Cosmos logo mark and brand colors.
- `Package.swift` - SwiftPM manifest. The app shell requires macOS 13+
  (`NavigationSplitView`); the shell scripts themselves still target macOS 11.

### How actions run

Two execution paths, picked per action:

- **Embedded** (`runCommand`): runs the script with `Process`, streaming stdout
  /stderr into the in-app console. Used for read-only or non-privileged actions
  that don't need a TTY — Launch Steam (`--steam`, detaches), Launch Profile,
  Detect Games (`--list`), **Verify Detection** (`--verify`), Open Logs, Profiles
  Folder, Reset Bottle (`--reset-bottle --force`), Refresh, **repair** actions
  (`repair.command install-dep` / `apply-fix`), **profile** actions
  (`profile.command show` / `apply`), **CosmosDB** (`cosmosdb.command lookup` /
  `report`), and all **bottle** actions (`bottle.command create/set/launch/logs/
  reset/delete`; reset/delete pass `--force` after the dashboard's own
  confirmation). When a bottle is selected, `COSMOS_BOTTLE` is passed in the
  environment for detection, repair, and profile commands.
- **Terminal** (`runInTerminal`): asks Terminal.app (via `osascript … do script`)
  to run the script. Used for actions that need `sudo` or interactive prompts the
  piped runner can't provide — **Install Cosmos**, **First-time setup** (in-app guide), **Full guided setup** (`setup.command`), **Prepare Bottle** (`run.command --setup-steam`), **Build Launchers**
  (`detect_steam_games.command --install`), and **Uninstall**. The dashboard
  launches Terminal and returns; the user completes any password/confirmation
  prompts there, then taps **Refresh**.

### Where configs live (dev vs installed app)

`detect_steam_games.command` and `install_cosmos.command` resolve their configs
directory the same way, so the dashboard can build launchers whether it runs from
a checkout or an installed bundle:

1. an explicit `COSMOS_CONFIGS_DIR` always wins;
2. when the script sits inside an installed app bundle (its directory ends in
   `.app/Contents/Resources`, which is read-only), generated configs/icons go to
   `~/Library/Application Support/Cosmos/cosmos_configs`, seeded once (no-clobber)
   with the curated configs shipped in the bundle;
3. otherwise (a dev checkout) the `cosmos_configs/` next to the script is used,
   exactly as before.

So generated `steam-*.conf` and icons never get written into the app bundle, and
an installed `Cosmos.app` can detect → build launchers without the repository.

### Build

```bash
swift build -c release            # compile the Cosmos executable
scripts/build_cosmos_app.command  # build ./build/Cosmos.app (bundles the scripts)
INSTALL=1 scripts/build_cosmos_app.command  # also copy it into /Applications
```

### Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

- **Build Cosmos app (SwiftPM)** — `swift build` (debug + release) on a macOS
  runner, so a dashboard that doesn't compile can't reach `main`.
- **Shell script syntax** — `bash -n` over every `*.command`/`*.sh`.

Run the same checks locally before pushing:

```bash
swift build                                                   # compile check
find . -type f \( -name '*.command' -o -name '*.sh' \) -print0 \
  | xargs -0 -n1 bash -n                                      # shell syntax
```

`build_cosmos_app.command` compiles via SwiftPM, then assembles a
double-clickable `Cosmos.app`. Into `Contents/Resources/` it copies the helper
scripts (`run.command`, `install_cosmos.command`, `uninstall.command`,
`detect_steam_games.command`, `make_app_icon.command`), the launcher template
(`app/cosmos/` — `CosmosLauncher` + `AppIcon.icns`), and the curated configs
(`cosmos_configs/`, minus any generated `steam-*.conf`/`icons/` and local
`overrides/*.env`). That makes the installed app self-contained: it can build
game launchers without the repository. Requires Xcode or the Command Line
Tools (`swift`).

## Auto-Detecting Steam Games

`detect_steam_games.command` scans the Steam libraries inside the Wine prefix and
turns each installed game into a launcher config, so you don't have to hand-write
a `.conf` per game.

How it works:

1. Finds Steam in the prefix (`Program Files (x86)/Steam` or `Program Files/Steam`).
2. Reads every library from `steamapps/libraryfolders.vdf`, mapping Windows paths
   to the filesystem through the prefix's `dosdevices/` drive symlinks.
3. Parses each `appmanifest_<appid>.acf` for the App ID and name. Skips partial
   downloads (via `StateFlags`) and stale manifests left after library moves
   (`*.acf.tmp.save`). Set `COSMOS_DETECT_INCLUDE_PARTIAL=1` to include
   in-progress installs.
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
