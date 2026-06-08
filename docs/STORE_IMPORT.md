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
| `list` | Show standalone configs in `cosmos_configs/` |
| `run-installer <file>` | Run `.exe` / `.msi` via `run.command --run-installer` |
| `add-exe <path> --name <title>` | Create `standalone-<slug>.conf` |
| `add-gog <setup.exe> --name <title>` | Run GOG offline installer, auto-find `.exe` |
| `add-itch <folder> --name <title>` | Copy itch.io download into prefix and register |

Use `--bottle <name>` to target a named bottle instead of the default prefix.

## Launcher config format

```sh
APP_NAME="My Game (Cosmos)"
BUNDLE_ID="com.cosmos.standalone-my-game"
RUN_ENV_NAMES=( GAME_EXE_PATH COSMOS_SKIP_STEAM )
GAME_EXE_PATH="drive_c/Games/my-game/game.exe"
COSMOS_SKIP_STEAM="1"
```

Optional: add `profiles/standalone/<slug>.yaml` for known-good settings (see
[PROFILE_FORMAT.md](PROFILE_FORMAT.md)).

## Epic (experiment)

Epic Games via [Legendary](https://github.com/heroic-games-launcher/legendary) is
planned as an experimental importer. For now, install with Legendary under Wine and
register the resulting `.exe` with `add-exe`.
