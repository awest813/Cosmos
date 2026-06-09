# Fix Recipes

One-click fixes applied by `repair.command` (roadmap 0.5). Profiles reference
these by ID in their `fixes:` list.

## Format (`*.recipe`)

```
TYPE=fix
ID=clear_steam_caches
DESCRIPTION=Remove Steam shader and HTTP caches inside the prefix
ACTION=script
SCRIPT=clear_steam_caches
```

Implementations live in `scripts/repair_fixes.sh`.

Recipes imported from [winemactricks-json](https://github.com/Alien4042x/winemactricks-json)
include `SOURCE=winemactricks:<id>` and may set `DLL_OVERRIDE` directly (no env required).

## Apply

```bash
./repair.command list-fixes
./repair.command apply-fix grounded-mscoree-fix
./repair.command apply-fix kill_wine
DLL_OVERRIDE="ddraw=n,b" ./repair.command apply-fix dll_override
STEAM_APPID=22380 ./repair.command apply-fix disable_intro_video
COSMOS_FORCE=1 ./repair.command apply-fix rebuild_prefix
COSMOS_BACKEND=wined3d ./repair.command apply-fix set_backend
./repair.command diagnose
./repair.command diagnose --log ~/Library/Application\ Support/Cosmos/logs/steam-launch.log
```

## Shipped fixes

| ID | Action |
| --- | --- |
| `kill_wine` | Terminate wineserver / Wine for `WINEPREFIX` |
| `clear_steam_caches` | Delete Steam httpcache/shadercache under prefix |
| `set_windows_version` | Apply `WINDOWS_VERSION` to prefix registry (requires env) |
| `disable_retina` | Turn off Wine Retina mode and persist `WINE_RETINA_MODE=0` |
| `dll_override` | Write `DllOverrides` registry keys (requires `DLL_OVERRIDE`) |
| `rebuild_prefix` | Delete prefix for a clean rebuild (set `COSMOS_FORCE=1` in scripts) |
| `force_borderless` | Disable display capture + Retina (common fullscreen fix) |
| `disable_intro_video` | Append `-novid` (or `INTRO_SKIP_ARGS`) to game overrides |
| `set_backend` | Persist `COSMOS_BACKEND` to bottle/steam settings (+ game override if `STEAM_APPID` set) |
| `reinstall_steam` | Remove Steam from the prefix and re-run `./run.command --install-steam` |
| `install_steamwebhelper_wrapper` | Build/install MIT `steamwebhelper.exe` wrapper (needs `mingw-w64`) |
| `seed_japanese_fonts` | Copy macOS CJK fonts + font substitution registry into prefix |
| `fix_steam_ssl` | Copy macOS CA bundle into prefix (`cacert.pem`) |
| `grounded-mscoree-fix` | Set `mscoree=n` (winemactricks-json; Unity/.NET black screen) |
| `apply_reg_commands` | Run pipe-separated `wine reg …` lines from `REG_COMMANDS` |

### Registry diff → recipe (wineregdiff)

```bash
./repair.command capture-reg before
# apply manual fix or winetricks verb
./repair.command capture-reg after
./repair.command diff-reg before after
./repair.command recipe-from-diff before after my-custom-fix
./repair.command apply-fix my-custom-fix
```

Requires [wineregdiff](https://github.com/castaneai/wineregdiff) (MIT).

## Diagnose

`repair.command diagnose` checks prefix health and scans the latest launch log for
common Wine/Steam failure patterns, then prints suggested `apply-fix` / `install-dep`
commands. Pass `--log <path>` to analyze a specific file.
