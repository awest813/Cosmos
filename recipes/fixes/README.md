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

## Apply

```bash
./repair.command list-fixes
./repair.command apply-fix kill_wine
DLL_OVERRIDE="ddraw=n,b" ./repair.command apply-fix dll_override
STEAM_APPID=22380 ./repair.command apply-fix disable_intro_video
COSMOS_FORCE=1 ./repair.command apply-fix rebuild_prefix
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
