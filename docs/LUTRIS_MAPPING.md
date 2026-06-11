# Lutris → Cosmos Profile Mapping

[Lutris](https://github.com/lutris/lutris) installer YAML describes how to install
and run Windows games on Linux. Cosmos **v0 profiles** ([PROFILE_FORMAT.md](PROFILE_FORMAT.md))
are the macOS equivalent: known-good launch settings, not full installers yet.

Use Lutris scripts as **recipe inspiration**; do not copy GPL installer YAML into
this LGPL repo without checking each file's license.

## Field mapping

| Lutris installer | Cosmos profile v0 | Notes |
| --- | --- | --- |
| `game_slug` / `name` | `id` / `name` | Display name vs stable slug |
| `game: exe` | `exe_path` (standalone) or Steam `steam_appid` | Steam games launch via `-applaunch` |
| `game: args` | `settings.env.STEAM_GAME_ARGS` or profile notes | Forwarded by `run.command` |
| `game: prefix` | Bottle / `WINEPREFIX` | Use `COSMOS_BOTTLE` or default prefix |
| `game: arch` | (bottle) | `win32` vs `win64` prefix — future bottle flag |
| `wine: overrides` | `fixes: dll_override` (planned) | e.g. `ddraw.dll=n` |
| `wine: dxvk` / runner | `recommended_backend` | `dxmt`, `d3dmetal`, `dxvk`, `wined3d` |
| `installer: wineexec` | `dependencies` + manual install notes | Map to winetricks verbs |
| `system: env` | `settings.env` | Key/value map |
| winetricks in script | `dependencies:` list | IDs in `recipes/dependencies/` |

## Example: Lutris-style steps → Cosmos profile

**Lutris (conceptual)**

```yaml
runner: wine
script:
  installer:
    - task:
        name: winetricks
        prefix: $GAMEDIR
        app: vcrun2015
  wine:
    overrides:
      d3d11.dll: native,builtin
  game:
    exe: $GAMEDIR/drive_c/...
```

**Cosmos profile**

```yaml
store: steam
steam_appid: 22380
recommended_backend: dxmt
settings:
  windows_version: win10
  env:
    STEAM_GAME_ARGS: ""
dependencies:
  - vcrun2015
fixes:
  - clear_steam_caches
```

**Apply**

```bash
./profile.command apply profiles/steam/steam-22380-fallout-new-vegas.yaml
```

This writes `cosmos_configs/overrides/<appid>.env`, runs winetricks deps, and
applies fix recipes.

## Winetricks verb → dependency recipe

Add a file `recipes/dependencies/<id>.recipe`:

```
TYPE=dependency
ID=vcrun2015
DESCRIPTION=Microsoft Visual C++ 2015-2022 Redistributable
WINETRICKS=vcrun2015
```

Reference [winetricks app list](https://github.com/Winetricks/winetricks/wiki/App-ID-List).
