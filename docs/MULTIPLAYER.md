# Multiplayer on Cosmos

Cosmos runs the **Windows Steam client** under Wine. In-game networking uses the
same Windows sockets stack as on Linux Proton — there is no separate macOS
netcode layer. What differs is **anti-cheat**, **overlay**, and **performance
primitives** (esync).

## What works

| Mode | Expectation |
| --- | --- |
| Steam friends / lobby join | Usually works for titles **without** kernel anti-cheat |
| LAN / direct IP | Works when the game supports it; no extra Cosmos config required |
| Steam cloud saves | Works (real Windows Steam client; Windows paths in Wine prefix) |
| Epic online (Legendary) | Experimental — see [STORE_IMPORT.md](STORE_IMPORT.md) |

## What does not work

| Blocker | Cosmos behavior |
| --- | --- |
| Easy Anti-Cheat / BattlEye / Ricochet | `status: blocked` profiles + pre-launch warning |
| Steam overlay (Shift+Tab invites) | Disabled by default for stability (`gameoverlayrenderer=d`) |
| Kernel-level VAC modules | Same limits as Proton on Linux — most VAC titles are fine, blocked titles are listed explicitly |

## Profile fields

Curated profiles can declare multiplayer metadata:

```yaml
tags:
  - co-op
  - online
anti_cheat: none
multiplayer_notes: "Apply fix_steam_networking if socket errors appear in logs."
settings:
  sync_mode: esync   # or legacy esync: true — exports COSMOS_SYNC_MODE in overrides/<appid>.env
fixes:
  - fix_steam_networking
```

Run `./profile.command show profiles/steam/steam-105600-terraria.yaml` to inspect.

## Fixes

| Recipe | When to use |
| --- | --- |
| `fix_steam_networking` | `steamnetworkingsockets` / UDP / bind errors in launch log |
| `fix_steam_ssl` | Steam client TLS (login/store) — not in-game netcode |
| `clear_steam_download_cache` | Stuck downloads before you can play online |
| `fix_steam_cloud_paths` | Verify userdata/save folders; clear stuck `remotecache.vdf` |

```bash
./repair.command diagnose --log ~/Library/Application\ Support/Cosmos/logs/steam-launch.log
./repair.command apply-fix fix_steam_networking
./repair.command apply-fix fix_steam_cloud_paths
```

Cloud saves use **Windows paths inside the Wine prefix**, not native macOS Steam.
If the same App ID is installed in both, see [STEAM_SETUP.md](STEAM_SETUP.md#steam-cloud-saves).

## Diagnose

`repair.command diagnose` scans launch logs for:

- Steam Networking / socket bind failures → suggests `fix_steam_networking`
- Easy Anti-Cheat / BattlEye strings → notes that the title may be `blocked`
- Download / depot errors → suggests `clear_steam_download_cache`

## Reporting

When a co-op title works (or fails) online, report via the dashboard compatibility
form and mention **multiplayer tested** in the notes. Future CosmosDB schema may
add structured `multiplayer.tested` fields.
