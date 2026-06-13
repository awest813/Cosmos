# Cosmos Graphics Backends

Cosmos treats Direct3D→Metal translation backends as **swappable tools**, chosen
per game (or per bottle). This mirrors how CrossOver Mac exposes D3DMetal, DXVK,
and WineD3D as selectable graphics options.

The UI keeps it simple:

```
Graphics Backend:
[ Recommended ]   ← default; uses the profile's recommended_backend
[ D3DMetal ]
[ DXMT ]
[ DXVK ]
[ WineD3D ]
```

Normal users pick **Recommended**. The profile decides what that resolves to.
Power users override it.

## Backend reference

| Backend | Translates | Best for | Notes |
| --- | --- | --- | --- |
| **D3DMetal / GPTK** | DX11 / DX12 → Metal | Many modern DX11/DX12 titles | Part of Apple's Game Porting Toolkit. **Not redistributable** — users supply their own GPTK install (see licensing). |
| **DXMT** | D3D10 / D3D11 → Metal | D3D10/11 games on Apple Silicon | Open Metal-based translation layer for Wine on macOS. Cosmos's current default backend. **Does not translate D3D9** — see below. |
| **DXVK + MoltenVK** | D3D9/10/11 → Vulkan → Metal | Some D3D9/10/11 cases | Goes through MoltenVK on macOS; extra translation hop. |
| **WineD3D** | D3D → OpenGL/Vulkan | Compatibility fallback | Slowest, broadest. Use when nothing else works. |
| **Software / OpenGL** | — | Old, weird games | Last-resort fallback. |

### A note on VKD3D-Proton

VKD3D-Proton can provide native Win32 `d3d12.dll` / `d3d12core.dll` replacements
in Wine, but it relies on DXGI pieces from DXVK. On Linux this is straightforward;
on macOS the path is more complicated because of the MoltenVK/Metal layering. Treat
Mac VKD3D as experimental rather than a first-class default.

## Direct3D 9 on macOS

DXMT (Cosmos's default backend) translates **D3D10 and D3D11** to Metal. It does
**not** implement D3D9. When a game uses Direct3D 9 on the default `dxmt` or
`recommended` backend, Wine's built-in **WineD3D** layer still handles those calls
(typically via OpenGL on modern Wine builds).

Many D3D9 titles run fine this way — curated profiles often keep
`recommended_backend: dxmt` for that reason. When they do not, work through the
steps below before chasing experimental stacks.

| Situation | What to do |
| --- | --- |
| **D3D9 game works on default `dxmt`** | Keep it. WineD3D handles D3D9 under the hood; no backend change needed. |
| **Glitches or poor performance** | Create a **dedicated bottle** with `COSMOS_BACKEND=wined3d` (dashboard **Bottles** tab or `bottle.conf`). WineD3D is slower but more forgiving for older D3D paths. |
| **Still broken on WineD3D** | Place **[dgVoodoo](http://dege.freeweb.hu/dgVoodoo2/)** in the game's folder to uplift D3D9 → D3D11, then keep **DXMT** as the bottle backend so DXMT can translate the D3D11 path. |
| **Experimental Vulkan path** | **KosmicKrisp** + DXVK may improve D3D9–11 coverage eventually, but it is not mature enough to be a Cosmos default. Track upstream; do not expect turnkey support yet. |

Per-game overrides: set `COSMOS_BACKEND=wined3d` in `overrides/<appid>.env` or the
game's `.conf` launcher config (see [PROFILE_FORMAT.md](PROFILE_FORMAT.md)).

> Use a **separate bottle per backend** so DXMT, WineD3D, and GPTK DLLs do not
> accumulate in the same prefix `system32`.

## How backends are selected today

`run.command` exposes the backend as a first-class selector via the
`COSMOS_BACKEND` environment variable (settable per game through a `.conf` /
`overrides/<appid>.env`, see [PROFILE_FORMAT.md](PROFILE_FORMAT.md)):

```
COSMOS_BACKEND = recommended | dxmt | d3dmetal | dxvk | wined3d
```

- **`recommended` (default):** resolves to `d3dmetal` when `GPTK_PATH` is set,
  otherwise `dxmt`. This preserves the historical `GPTK_PATH`-driven behavior, so
  existing setups are unaffected.
- **`dxmt`:** downloaded into `~/DXMT` and enabled via `WINEDLLPATH_PREPEND`;
  `DXMT_LOG_LEVEL` defaults to `error`. Tuned per game via the `DXMT_CONFIG` env
  var (e.g. `d3d11.preferredMaxFrameRate=60;`). No setup required.
- **`d3dmetal`:** needs `GPTK_PATH` pointing at a user-supplied Game Porting
  Toolkit install. Cosmos copies the D3DMetal DLLs into the prefix's `system32`
  and sets `WINEDLLOVERRIDES=d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n`.
- **`dxvk` (experimental):** needs `DXVK_PATH` pointing at a folder of DXVK DLLs.
  Cosmos copies them into `system32` and sets the DXVK overrides. On macOS DXVK
  routes through MoltenVK (Vulkan→Metal), which must be installed separately.
- **`wined3d`:** forces Wine's built-in Direct3D→OpenGL with
  `WINEDLLOVERRIDES=…=b`; no downloads. Broadest compatibility, slowest — a
  fallback when nothing else works.

### Thread sync (Phase E)

Set `COSMOS_SYNC_MODE` in `steam.conf`, a bottle's `bottle.conf`, or a per-game
override:

| Mode | Wine env | Use when |
| --- | --- | --- |
| `off` | (none) | Default |
| `esync` | `WINEESYNC=1` | Multiplayer / lower CPU overhead |
| `msync` | `WINEMSYNC=1` | Experimental newer sync path |

The dashboard **Performance & Graphics** section exposes this for the default Steam
bottle; per-bottle pickers live under **Bottles**.

### D3D12 / GPTK setup

D3D12 titles need Apple's Game Porting Toolkit (not redistributed). Use the dashboard
**D3D12 — Game Porting Toolkit** card: browse to your install, **Validate**, then
**Save & Test Steam**. Set `COSMOS_BACKEND=d3dmetal` (or `recommended` with
`GPTK_PATH` set).

> A dedicated bottle per backend is recommended so native DLLs from different
> backends don't accumulate in one `system32`. The 0.3 bottle manager and a UI
> backend picker build on this selector.

## Licensing

- **D3DMetal / GPTK is Apple proprietary.** Apple's EULA forbids redistribution.
  Cosmos must **not** bundle or download it — users point Cosmos at their own
  install obtained from developer.apple.com.
- **DXMT, DXVK, MoltenVK, WineD3D** are open source and may be bundled where their
  licenses allow. Cosmos pins **DXMT 0.80** by default; the **Latest (LGPL)**
  channel tracks newer releases — see [LICENSING.md](LICENSING.md) and
  `runtime/DXMT-SOURCE-OFFER.txt`.
</content>
