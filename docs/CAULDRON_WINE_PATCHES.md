# Cauldron Wine patches — Cosmos relevance

[Cauldron](https://github.com/cashcon57/cauldron) maintains a **custom Wine 11.6 fork**
with macOS-specific and gaming-critical patches. Cosmos ships **Gcenx Wine tarballs**
([RUNTIME.md](RUNTIME.md)) and does **not** apply Cauldron's patch series today.

This document records which Cauldron patches matter for macOS gaming, what Cosmos can
do without a custom Wine build, and what belongs on the runtime roadmap.

## Cauldron-owned patches (`patches/cauldron/`)

| Patch | Component | Problem | Cosmos today | Roadmap |
| --- | --- | --- | --- | --- |
| **0001** VirtualProtect COW | `ntdll` | SKSE/F4SE/ASI loaders patch `.text` in memory; Wine reloads file-backed pages on `VirtualProtect` → mods vanish ([Wine #29384](https://bugs.winehq.org/show_bug.cgi?id=29384)) | **No fix** in stock Gcenx Wine. Modded Bethesda titles may fail silently. Document in Skyrim/FNV/F4 profiles. | Track upstream + CodeWeavers; evaluate cherry-pick onto pinned Gcenx when stable. |
| **0003** macdrv compositor flicker | `winemac.drv` | Fullscreen/windowed flicker on macOS compositor | Partial overlap: `force_borderless`, Retina off, virtual desktop in `steam.conf` | Monitor wine-staging `winemac.drv-no-flicker`; port if Gcenx lacks it. |
| **0004** Native DLLs from app dir | `ntdll` loadorder | DXMT/DXVK DLLs in game folder lose to builtins when Steam spawns child processes without env | **Workaround:** `WINEDLLOVERRIDES` in `steam.conf`, per-game overrides, prefix `system32` copy in `run.command` | Desirable upstream; reduces per-game override boilerplate. |

### VirtualProtect COW (highest impact)

Cauldron's README calls this out for **SKSE, F4SE, OBSE, ENBSeries, ReShade, ASI
loaders**. Cosmos profiles already recommend direct launch and `force_borderless` for
Skyrim SE, but **in-memory code caves still break** on stock Wine without patch 0001.

**User guidance until a patched Wine ships:**

- Test modded play on a Windows VM or CrossOver if script extenders fail after load.
- Prefer launchers that do not `VirtualProtect` the main exe when possible.
- Watch [Wine #29384](https://bugs.winehq.org/show_bug.cgi?id=29384) and Gcenx release notes.

### Native DLL search order (patch 0004)

Cauldron stages `d3d11.dll` / `dxgi.dll` next to the game exe and patches the loader
so graphics DLLs win without `WINEDLLOVERRIDES`. Cosmos instead:

1. Copies DXMT/DXVK DLLs into prefix `system32` via `run.command --setup-steam`
2. Sets global `COSMOS_STEAM_WINEDLLOVERRIDES` for Steam + games
3. Protects `steamwebhelper.exe` with builtin overrides (same goal as Cauldron step 8)

Per-game `WINEDLLOVERRIDES` in profile `settings.env` covers stubborn titles.

## Cauldron patch audit — tiers worth tracking

From Cauldron [`patches/PATCH_AUDIT.md`](https://github.com/cashcon57/cauldron/blob/main/patches/PATCH_AUDIT.md)
(Wine 11.6 base). Cosmos does not maintain these; use as a **cherry-pick checklist**
when rebasing on a newer Gcenx pin.

### Tier 1 — gaming critical (wine-staging + Cauldron)

| Patch area | Why it matters on macOS |
| --- | --- |
| `ntdll-WRITECOPY` / Cauldron 0001 | Mod loaders (see above) |
| `wined3d-zero-inf-shaders` | Shader compile failures on D3D9/OpenGL path |
| `wined3d-unset-flip-gdi` | Display flip / GDI interaction |
| `d3dx9_36-D3DXStubs` | Older D3D9 titles missing D3DX |
| `dxgi_getFrameStatistics` | Frame pacing / overlay tools |

**Cosmos mitigation:** `wined3d` bottle, dgVoodoo uplift, SpockD3D9 experimental PE
`d3d9.dll` — see [BACKENDS.md](BACKENDS.md).

### Tier 2 — stability

| Patch area | Typical symptom |
| --- | --- |
| `kernel32-limit_heap_old_exe` | 32-bit legacy games OOM |
| `ntdll-Exception` | Crash on structured exception |
| `vcomp_for_dynamic_init_i8` | OpenMP in game engines |

**Cosmos mitigation:** `WINE_CPU_TOPOLOGY`, `sync_mode: off`, `windows_version` in
profiles (ported from Cauldron seed).

### Tier 4 — Proton cherry-picks (selected)

| Proton patch theme | Cosmos note |
| --- | --- |
| `NtProtectVirtualMemory` range scan | Overlaps Cauldron 0001 problem space |
| `win32u` GPU info in registry | Games that probe DXGI adapter vendor |
| `xaudio2` / `xaudio2_8` | Audio crackle — profile `STAGING_AUDIO_PERIOD` |
| `windows.storage` stub | UWP/Store API shims |

Most Proton patches are **already in Wine 11.x** upstream; Cauldron's audit shows
~60 absorbed when moving 10.0 → 11.6. Cosmos pins Gcenx 11.8 — prefer **upstream
merge status** over re-applying old Proton diffs.

## Graphics stack patches (Cauldron audit)

| Component | Wine patches required? | Cosmos |
| --- | --- | --- |
| DXMT | winemetal / macdrv symbols (CrossOver lineage) | Auto-download DXMT; prefix `system32` install |
| DXVK-macOS | No (drop-in DLLs) | Experimental `COSMOS_BACKEND=dxvk` |
| KosmicKrisp | Build against `libvulkan.dylib` ICD | Documented experimental only |
| D3DMetal / GPTK | No (user-supplied) | `GPTK_PATH` + `d3dmetal` backend |
| MoltenVK | No | DXVK path dependency |

## msync / Rosetta patches (`patches/rosetta/`)

Cauldron adapts CrossOver's Rosetta hack series for Apple Silicon x86 Wine builds.
Cosmos runs WoW64 Gcenx builds under Rosetta 2 on arm64 — same constraint, different
packaging.

| Item | Status in Cauldron audit | Cosmos |
| --- | --- | --- |
| wine-msync (4 patches) | Conflict with upstream; needs rebase | `COSMOS_SYNC_MODE=msync` when Gcenx build supports `WINEMSYNC=1` |
| proton-slr macOS (37 patches) | Mostly conflict | Track Gcenx release notes; no in-tree fork |

## Policy: reference, don't fork (yet)

1. **Profiles and env workarounds first** — CPU topology, sync off, audio period,
   launcher bypasses (see [CAULDRON.md](CAULDRON.md)).
2. **Track upstream** — Wine #29384, wine-staging gaming patches, Gcenx changelog.
   Status table: [ROADMAP.md §1.0 tracked Wine gaps](ROADMAP.md#tracked-wine-gaps-gcenx-pin).
3. **Cherry-pick only with CI** — Any custom Wine pin needs macOS launch regression
   tests (Skyrim SE + SKSE, Fallout 4 + F4SE, Steam CEF).
4. **LGPL compliance** — Forked Wine must ship source offers per [LICENSING.md](LICENSING.md).

## Related docs

- [CAULDRON.md](CAULDRON.md) — profile field mapping and ported batches
- [BACKENDS.md](BACKENDS.md) — graphics escalation
- [ADOPTION_PLAN.md](ADOPTION_PLAN.md) — Gcenx Runtime 1.0 pinning
- Upstream: [cauldron/patches/PATCH_AUDIT.md](https://github.com/cashcon57/cauldron/blob/main/patches/PATCH_AUDIT.md)
