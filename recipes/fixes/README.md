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
```

## Shipped fixes

| ID | Action |
| --- | --- |
| `kill_wine` | Terminate wineserver / Wine for `WINEPREFIX` |
| `clear_steam_caches` | Delete Steam httpcache/shadercache under prefix |
| `set_windows_version` | Documents `WINDOWS_VERSION`; set via bottle/steam.conf |

## Planned

- `disable_intro_video`, `force_borderless`, `dll_override`, `rebuild_prefix`
</content>
