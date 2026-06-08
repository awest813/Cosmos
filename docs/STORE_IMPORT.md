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
| `list` | Show standalone and Epic configs in `cosmos_configs/` |
| `run-installer <file>` | Run `.exe` / `.msi` via `run.command --run-installer` |
| `add-exe <path> --name <title>` | Create `standalone-<slug>.conf` |
| `add-gog <setup.exe> --name <title>` | Run GOG offline installer, auto-find `.exe` |
| `add-itch <folder> --name <title>` | Copy itch.io download into prefix and register |
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

Optional: add `profiles/standalone/<slug>.yaml` for known-good settings (see
[PROFILE_FORMAT.md](PROFILE_FORMAT.md)).

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
