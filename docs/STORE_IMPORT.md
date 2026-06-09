# Store Import (roadmap 0.6)

Cosmos can register non-Steam Windows games as first-class `.app` launchers using
`import_game.command`. Imported games use `GAME_EXE_PATH` and skip Steam install
(`COSMOS_SKIP_STEAM=1`).

## Quick start

```bash
# 1. Run an installer inside your Wine prefix
./import_game.command run-installer ~/Downloads/GameSetup.exe

# 2. Register the installed .exe (path relative to prefix or drive_c/...)
./import_game.command add-exe "drive_c/Program Files/My Game/game.exe" --name "My Game"

# 3. Build the macOS launcher
./install_cosmos.command
```

## Commands

| Command | Purpose |
| --- | --- |
| `list` | Show standalone, GOG, itch, Battle.net, and Epic configs in `cosmos_configs/` |
| `run-installer <file>` | Run `.exe` / `.msi` via `run.command --run-installer` |
| `add-exe <path> --name <title>` | Create `standalone-<slug>.conf` |
| `add-gog <setup\|slug\|path> --name <title>` | Run GOG offline installer or register an installed game |
| `list-gog` | List GOG games detected under `drive_c/GOG Games` |
| `add-itch <folder> --name <title>` | Copy itch.io download into prefix; creates `itch-<slug>.conf` |
| `install-battlenet <setup.exe>` | Install the Battle.net desktop app in the prefix |
| `list-battlenet` | List Blizzard games detected under Program Files |
| `add-battlenet <path\|slug> --name <title>` | Register a Battle.net game as `battlenet-<slug>.conf` |
| `auth-epic` | Log in to Epic via `legendary auth` |
| `list-epic` | List Windows Epic titles and installed games |
| `add-epic <app> --name <title> [--install]` | Install/register via Legendary |

Use `--bottle <name>` to target a named bottle instead of the default prefix.

## Launcher config format

```sh
APP_NAME="My Game (Cosmos)"
BUNDLE_ID="com.cosmos.standalone-my-game"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM )
GAME_EXE_PATH="drive_c/Games/my-game/game.exe"
COSMOS_SKIP_STEAM="1"
```

GOG offline imports use `gog-<slug>.conf` and install into `drive_c/GOG Games/` by
default (GOG Galaxy paths are also scanned):

```sh
APP_NAME="The Witcher 3 (Cosmos)"
BUNDLE_ID="com.cosmos.gog-the-witcher-3"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM )
GAME_EXE_PATH="drive_c/GOG Games/The Witcher 3 Wild Hunt GOTY/bin/x64/witcher3.exe"
COSMOS_SKIP_STEAM="1"
```

itch.io imports use the `itch-<slug>.conf` prefix so they are easy to tell apart
from generic standalone games:

```sh
APP_NAME="Celeste Classic (Cosmos)"
BUNDLE_ID="com.cosmos.itch-celeste-classic"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM )
GAME_EXE_PATH="drive_c/Games/celeste-classic/celeste.exe"
COSMOS_SKIP_STEAM="1"
```

Battle.net imports set `BATTLENET_LAUNCHER_EXE` when the client is installed so
Cosmos can start the agent before launching the game:

```sh
APP_NAME="StarCraft II (Cosmos)"
BUNDLE_ID="com.cosmos.battlenet-starcraft-ii"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM BATTLENET_LAUNCHER_EXE )
GAME_EXE_PATH="drive_c/Program Files (x86)/StarCraft II/..."
COSMOS_SKIP_STEAM="1"
BATTLENET_LAUNCHER_EXE="drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
```

Epic imports also set `LEGENDARY_APP_NAME` so Cosmos can launch through Legendary
for online authentication:

```sh
APP_NAME="Super Meat Boy (Cosmos)"
BUNDLE_ID="com.cosmos.epic-smb"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM LEGENDARY_APP_NAME )
GAME_EXE_PATH="/Users/you/Games/SuperMeatBoy/SuperMeatBoy.exe"
COSMOS_SKIP_STEAM="1"
LEGENDARY_APP_NAME="Sugar"
```

Optional: add store-specific YAML profiles for known-good settings (see
[PROFILE_FORMAT.md](PROFILE_FORMAT.md)):

- `profiles/standalone/<slug>.yaml`
- `profiles/gog/gog-<slug>.yaml`
- `profiles/itch/itch-<slug>.yaml`
- `profiles/battlenet/battlenet-<slug>.yaml`

## GOG offline installers

Cosmos runs GOG `setup.exe` installers inside your Wine prefix, finds the main
game executable (skipping redistributables and uninstall helpers), and registers
a `gog-<slug>.conf` launcher.

### Import flow

```bash
# 1. Run the GOG offline installer and register the game
./import_game.command add-gog ~/Downloads/setup_celeste_1.2.3.exe --name "Celeste"

# 2. Or register an already-installed GOG folder by slug from list-gog
./import_game.command list-gog
./import_game.command add-gog celeste --name "Celeste"

# 3. Build the .app launcher
./install_cosmos.command
```

### Notes

- **GOG Galaxy** is not supported — use offline `setup.exe` installers only.
- Games install to `drive_c/GOG Games/<title>/` by default; Cosmos scans that path
  and GOG Galaxy `Games` folders when present.
- DRM-free titles launch directly via `GAME_EXE_PATH`; no Galaxy bootstrap is required.

## Battle.net / Blizzard

Cosmos installs the official Battle.net desktop app in your Wine prefix, detects
common Blizzard game folders, and registers launchers that start the Battle.net
agent when needed.

### Import flow

```bash
# 1. Install the Battle.net client
./import_game.command install-battlenet ~/Downloads/Battle.net-Setup.exe

# 2. Install games through the Battle.net app (inside Wine), then list them
./import_game.command list-battlenet

# 3. Register by slug from list-battlenet, or by direct .exe path
./import_game.command add-battlenet starcraft-ii --name "StarCraft II"

# 4. Build the .app launcher
./install_cosmos.command
```

### Notes

- Online titles may require the Battle.net agent; Cosmos starts it automatically
  when `BATTLENET_LAUNCHER_EXE` is set in the launcher config.
- Anti-cheat and kernel-level DRM titles (e.g. Overwatch 2) may still be
  **blocked** on macOS — check community reports before playing.
- Use `--bottle <name>` to target a named bottle instead of the default prefix.

## Epic via Legendary (experiment)

[Legendary](https://github.com/derrod/legendary) is an open-source Epic Games CLI.
Cosmos uses it to download Windows builds and register launchers — no official
Epic launcher required.

### Install Legendary

```bash
brew install legendary-gl
# or: pip install legendary-gl
```

### Import flow

```bash
# 1. Authenticate (opens browser)
./import_game.command auth-epic

# 2. List Windows titles in your library
./import_game.command list-epic

# 3. Install and register (use the App name column, not always the title)
./import_game.command add-epic Sugar --name "Super Meat Boy" --install

# 4. Build the .app launcher
./install_cosmos.command
```

Legendary downloads games to `~/Games/` by default. Cosmos stores the host path in
`GAME_EXE_PATH` and launches via Legendary + your Cosmos Wine prefix when
`LEGENDARY_APP_NAME` is set.

For offline-only play, set `LEGENDARY_OFFLINE=1` in the launcher env or use
`legendary launch --offline` manually.

### Notes

- Use `--platform Windows` when installing (Cosmos does this automatically).
- Multiplayer / DRM titles may need Legendary launch instead of direct `wine`.
- Legendary is third-party software; review its license and use at your own risk.
