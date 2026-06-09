# GOG profiles

YAML profiles for GOG offline installs registered via `import_game.command add-gog`.

Filename convention: `gog-<slug>.yaml` (slug matches `gog-<slug>.conf` in `cosmos_configs/`).

Required fields for `store: gog`:

- `exe_path` — prefix-relative path to the game executable (e.g. `drive_c/GOG Games/Celeste/celeste.exe`)

GOG Galaxy client installs are not fully supported; profiles target offline `setup.exe` installs under `drive_c/GOG Games/`.
