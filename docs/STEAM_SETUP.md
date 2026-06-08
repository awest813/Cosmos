# Steam setup (manual fallback)

Cosmos normally sets up Steam through the dashboard or `./run.command`. Use this
guide when you prefer Terminal, need to debug a failed setup, or the app cannot
run the embedded scripts.

## Prerequisites

- **macOS** on **Apple Silicon** (arm64). Cosmos does not support Intel Macs.
- **macOS 11+** (Big Sur or newer). Sequoia is the primary test target.
- **Rosetta 2** — installed automatically on first launch if missing (requires
  your password).
- Enough disk space for Wine (~2 GB), DXMT (~500 MB), and your Steam library
  (often 100 GB+ inside the prefix).

## Quick setup (recommended)

**Easiest:** open Cosmos.app and use the **First-time setup** guide (one button per step), or run the all-in-one script:

```bash
./setup.command
```

From the repository checkout (or the scripts inside `Cosmos.app` → Show Package
Contents → Resources):

```bash
./install_cosmos.command    # optional: install /Applications/Cosmos Apps launchers
./run.command --setup-steam # download Wine, create prefix, install Steam — no launch
./run.command --steam       # launch Steam (detached from Terminal by default)
```

In the **Cosmos** dashboard:

1. **Install Cosmos** (Terminal, may ask for `sudo`).
2. **Prepare Bottle** (Terminal — same as `--setup-steam`).
3. **Launch Steam** — sign in and install a Windows game.
4. **Detect Games** → **Build Launchers**.

## What `--setup-steam` does

`run.command --setup-steam` runs the same preparation as a normal Steam launch,
but **does not start `steam.exe`** afterward:

1. Validates macOS version and installs Rosetta if needed.
2. Downloads the pinned Wine build to `~/wine-<version>/` (if missing).
3. Creates the Wine prefix at `~/.wine-steam-11` (or `WINEPREFIX`).
4. Applies registry tweaks (Retina mode, Windows version, mouse acceleration).
5. Downloads the official `SteamSetup.exe` and installs Steam if it is not
   already in the prefix. By default this runs **unattended** (no wizard
   clicks); if the silent install can't finish it falls back to the graphical
   wizard. Set `COSMOS_STEAM_SILENT=0` (or turn off **Unattended Steam install**
   in the dashboard) to always use the wizard.
6. Installs and enables the selected graphics backend (DXMT by default).

Settings come from `~/Library/Application Support/Cosmos/steam.conf` (or
environment variables). The dashboard **Steam Wine Settings** section edits that
file.

## Persistent paths

| Item | Default location |
|------|------------------|
| Wine prefix | `~/.wine-steam-11` |
| Steam settings | `~/Library/Application Support/Cosmos/steam.conf` |
| Detached launch log | `~/Library/Application Support/Cosmos/logs/steam-launch.log` |
| Saved game profiles | `~/Library/Application Support/Cosmos/Profiles/` |
| Generated configs | `~/Library/Application Support/Cosmos/cosmos_configs/` |

Override any of these with environment variables before running `run.command`
(see [README_DEV.md](../README_DEV.md)).

## Install Steam only (prefix already exists)

If Wine and the prefix are ready but Steam is missing (or a previous install
left a broken Steam folder without `steam.exe`):

```bash
./run.command --install-steam
```

By default this runs unattended and falls back to the graphical wizard if
needed. To reinstall from scratch (including when Steam is already present):

```bash
./repair.command apply-fix reinstall_steam
```

`--setup-steam` still works and performs a full bottle prep (Wine, backend, and
Steam) when you want everything refreshed in one step.

## Check your setup status

Not sure where you are in setup? Run a quick, read-only diagnostic that mirrors
the dashboard checklist and tells you the next step:

```bash
./run.command --status
```

It reports whether Wine is downloaded, the prefix is created, Steam is
installed, and how many game launchers exist — then prints the recommended next
command. It never modifies the prefix, so it is safe to run any time.

## Launch without setup

If everything is already installed:

```bash
./run.command --steam
```

With `COSMOS_DETACH=1` (default), Steam keeps running after you close Terminal.
Logs go to `COSMOS_LAUNCH_LOG` (see table above).

Cosmos passes Wine-friendly Steam flags by default (`STEAM_LAUNCH_ARGS` in
`steam.conf`, currently `-no-cef-sandbox -cef-single-process`) and clears stale
Chromium lock files before each launch — patterns adapted from MIT
[steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine). Set
`STEAM_LAUNCH_ARGS=""` to opt out.

Launch a specific game by App ID:

```bash
STEAM_GAME_ID=250900 ./run.command --steam
```

## Troubleshooting

### Where am I in setup?

Run `./run.command --status` for a read-only summary of what is done and what
to run next.

### Steam won't start

1. Open the launch log:
   ```bash
   ./run.command --logs
   ```
   Or read `~/Library/Application Support/Cosmos/logs/steam-launch.log`.
2. Quit any running Steam/Wine using the prefix:
   ```bash
   ./repair.command apply-fix kill_wine
   ```
3. Clear Steam caches (safe; Steam re-downloads):
   ```bash
   ./repair.command apply-fix clear_steam_caches
   ```
4. Reset the prefix and start over:
   ```bash
   ./run.command --reset-bottle --force
   ./run.command --setup-steam
   ```

### "Wine is already using this prefix"

Steam or another Wine app is still running. Exit Steam from its menu
(**Steam → Exit**), or run `kill_wine` as above, then launch again.

### Backend errors

- **DXMT** (default): no extra setup.
- **d3dmetal**: set `GPTK_PATH` to your Apple Game Porting Toolkit install.
- **dxvk**: set `DXVK_PATH` and install MoltenVK (experimental on macOS).

See [BACKENDS.md](BACKENDS.md).

### Detection finds no games

Steam must be installed and you need at least one Windows game downloaded in the
prefix. Then:

```bash
./detect_steam_games.command --list
./detect_steam_games.command --verify
```

### Invalid `steam.conf`

Cosmos clamps unknown values on launch. Delete or fix
`~/Library/Application Support/Cosmos/steam.conf`; the dashboard can recreate
defaults.

## Named bottles (advanced)

To isolate Steam in a separate prefix with its own backend:

```bash
./bottle.command create steam --backend dxmt --windows win10
COSMOS_BOTTLE=steam ./run.command --setup-steam
./bottle.command launch steam --steam
```

For the default Steam bottle, leave `COSMOS_BOTTLE` unset.

## Related docs

- [README.md](../README.md) — user-facing overview
- [README_DEV.md](../README_DEV.md) — environment variables and script reference
- [ROADMAP.md](ROADMAP.md) — milestone status
- [BACKENDS.md](BACKENDS.md) — graphics backend selection
