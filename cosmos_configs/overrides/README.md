# Per-game overrides (auto-detected Steam games)

`detect_steam_games.command` regenerates `cosmos_configs/steam-<appid>-<slug>.conf`
every time it runs, so edits made directly to those files are overwritten. To
attach **persistent** per-game settings to an auto-detected game, drop a file here
named after its Steam App ID:

```
cosmos_configs/overrides/<appid>.env
```

Each line is a simple `KEY=VALUE` assignment. On the next detect/refresh, the
matching keys are added to the generated launcher's `RUN_ENV_NAMES` and the
assignments are appended to the config, so they ride along into the built `.app`.

```sh
# cosmos_configs/overrides/250900.env  (The Binding of Isaac: Rebirth)

# Graphics / backend tuning
DXMT_CONFIG="d3d11.preferredMaxFrameRate=60;"

# Extra arguments handed to the game (Steam forwards anything after the App ID)
STEAM_GAME_ARGS="-windowed -novid"

# Switch this game to Apple's D3DMetal backend instead of DXMT by pointing at a
# Game Porting Toolkit install (not redistributed by Cosmos).
# GPTK_PATH="/Users/you/GPTK"
```

Rules:

- The key must be upper-snake-case (`^[A-Z][A-Z0-9_]*$`); other lines, comments
  (`#`), and blanks are ignored, so an override file cannot inject arbitrary shell
  into the sourced config.
- `STEAM_GAME_ID` is reserved — it is always set from the detected App ID.
- Overrides only apply to **auto-generated** launchers. A hand-curated config for
  the same App ID wins outright and is never touched.

Recognized runtime variables include `DXMT_CONFIG`, `STEAM_GAME_ARGS`,
`WINE_RETINA_MODE`, `WINE_MOUSE_WARP_OVERRIDE`, `GPTK_PATH`, and any other
environment variable honored by `run.command`.

Files in this folder are not committed by default (other than this README and the
`*.example`); they are your local machine's settings.
