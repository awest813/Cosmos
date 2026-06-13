# Cauldron reference and profile porting

[Cauldron](https://github.com/cashcon57/cauldron) is an LGPL-2.1 macOS game
compatibility layer (Wine fork + Rust core + SwiftUI). The project is **paused**
but its `db/seed.sql` contains valuable per-game launch intelligence that Cosmos
can adopt as curated YAML profiles.

Cosmos does not ship Cauldron code. This document maps Cauldron concepts to
Cosmos equivalents and lists what has been ported.

## Field mapping

| Cauldron (`game_recommended_settings`) | Cosmos profile |
| --- | --- |
| `graphics_backend` | `recommended_backend` (`dxmt`, `d3dmetal`, `dxvk`, `wined3d`) |
| `msync_enabled` / `esync_enabled` = 0 | `settings.sync_mode: off` |
| `windows_version` | `settings.windows_version` |
| `cpu_topology` | `settings.env.WINE_CPU_TOPOLOGY` |
| `env_vars` (JSON) | `settings.env.*` |
| `launch_args` | `settings.env.STEAM_GAME_ARGS` |
| `exe_override` | `launch_method: direct` (+ optional `exe_path` relative to install) |
| `registry_entries` | `fixes:` recipes (`force_borderless`, `disable_retina`, `apply_reg_commands`) or manual `wine reg` |
| `audio_latency_ms` | `settings.env.STAGING_AUDIO_PERIOD` |
| `required_dependencies` | `dependencies:` (winetricks recipe IDs) |
| `wine_dll_overrides` | `settings.env.WINEDLLOVERRIDES` |
| `hidpi_mode` | `settings.retina` |

## Escalation paths Cauldron documents

Cauldron's graphics table aligns with [BACKENDS.md](BACKENDS.md):

| Backend | Cauldron name | Cosmos |
| --- | --- | --- |
| DXMT | DXMT | `COSMOS_BACKEND=dxmt` (default) |
| D3DMetal / GPTK | D3DMetal | `COSMOS_BACKEND=d3dmetal` + user GPTK |
| DXVK-macOS | DXVK-macOS | `COSMOS_BACKEND=dxvk` (experimental) |
| KosmicKrisp + DXVK | DXVK+KosmicKrisp | Documented experimental; not default |
| WineD3D | (fallback) | `COSMOS_BACKEND=wined3d` |

For D3D9-specific work, see also [SpockD3D9](https://github.com/awest813/SpockD3D9)
(maintainer fork) in BACKENDS.md.

## Launch techniques worth adopting

From Cauldron's launch pipeline (see upstream README):

1. **`steamwebhelper.exe` protection** — Cosmos already forces builtin D3D for
   Steam CEF via `COSMOS_STEAM_WINEDLLOVERRIDES` in `steam.conf`.
2. **Launcher bypasses** — `launch_method: direct` skips broken Steam launchers
   (Borderlands 2, Conan Exiles, SKSE/F4SE loaders).
3. **Sync disable** — Some UE2/older titles crash with esync/msync; use
   `settings.sync_mode: off` in the profile.
4. **CPU topology** — Far Cry / The Forest engines crash when Wine exposes too
   many cores; set `WINE_CPU_TOPOLOGY` in `settings.env`.
5. **macdrv per-app registry** — Skyrim SE cursor ghosting: `force_borderless`
   fix or manual `AppDefaults\<exe>\Mac Driver` keys.

## Wine fork patches (not bundled)

Cauldron's custom Wine 11.6 fork includes macOS-specific patches (VirtualProtect
COW for SKSE/F4SE, native DLL search order, macdrv flicker). Cosmos uses Gcenx
Wine — see [CAULDRON_WINE_PATCHES.md](CAULDRON_WINE_PATCHES.md) for impact and
workarounds.

## Refreshing hints from upstream

```bash
./scripts/import_cauldron_hints.sh --list
./scripts/import_cauldron_hints.sh --diff
```

The script fetches `db/seed.sql` from GitHub and prints portable settings.
Re-run after Cauldron updates to find new candidates for Cosmos profiles.

## Ported profile batches

**2026-06 (batch 2)** — Far Cry series, sync-off strategy titles, launcher bypasses:

- Added: Far Cry 3, 4, 5, Primal, Blood Dragon
- Added: Yakuza Kiwami, Supreme Commander: Forged Alliance, Total War: Rome II,
  Dead or Alive 5, State of Decay 2, Little Nightmares, Dawn of War II, Prototype,
  Conan Exiles, Evil Genius 2, Strange Brigade, The Evil Within
- Documented: [CAULDRON_WINE_PATCHES.md](CAULDRON_WINE_PATCHES.md)

**2026-06 (batch 1)** — Initial port from Cauldron `db/seed.sql`:

- Updated: BioShock, Skyrim SE, The Forest
- Added: Borderlands 2, Borderlands: The Pre-Sequel, BioShock 2 Remastered,
  Age of Empires III, Far Cry 2, HITMAN 3, Dark Souls: Prepare to Die Edition,
  Yakuza 0

Attribution: compatibility notes derived from
[Cauldron seed data](https://github.com/cashcon57/cauldron/blob/main/db/seed.sql)
(LGPL-2.1).
