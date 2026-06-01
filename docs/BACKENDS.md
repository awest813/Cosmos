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
| **DXMT** | D3D10 / D3D11 → Metal | D3D10/11 games on Apple Silicon | Open Metal-based translation layer for Wine on macOS. Cosmos's current default backend. |
| **DXVK + MoltenVK** | D3D9/10/11 → Vulkan → Metal | Some D3D9/10/11 cases | Goes through MoltenVK on macOS; extra translation hop. |
| **WineD3D** | D3D → OpenGL/Vulkan | Compatibility fallback | Slowest, broadest. Use when nothing else works. |
| **Software / OpenGL** | — | Old, weird games | Last-resort fallback. |

### A note on VKD3D-Proton

VKD3D-Proton can provide native Win32 `d3d12.dll` / `d3d12core.dll` replacements
in Wine, but it relies on DXGI pieces from DXVK. On Linux this is straightforward;
on macOS the path is more complicated because of the MoltenVK/Metal layering. Treat
Mac VKD3D as experimental rather than a first-class default.

## How backends are selected today

The current `run.command` already implements a two-backend version of this:

- **DXMT (default):** downloaded into `~/DXMT` and enabled via
  `WINEDLLPATH_PREPEND`; `DXMT_LOG_LEVEL` defaults to `error`. Tuned per game via
  the `DXMT_CONFIG` env var (e.g. `d3d11.preferredMaxFrameRate=60;`).
- **D3DMetal / GPTK (opt-in):** activated by setting `GPTK_PATH` to a
  user-supplied Game Porting Toolkit install. Cosmos copies the D3DMetal DLLs into
  the prefix's `system32` and sets
  `WINEDLLOVERRIDES=d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n`. A dedicated
  prefix is recommended so GPTK and DXMT DLLs don't mix.

The roadmap (0.3) turns this env-driven choice into a first-class `backend` enum
selectable from the UI, with DXVK and WineD3D added as additional options.

## Licensing

- **D3DMetal / GPTK is Apple proprietary.** Apple's EULA forbids redistribution.
  Cosmos must **not** bundle or download it — users point Cosmos at their own
  install obtained from developer.apple.com.
- **DXMT, DXVK, MoltenVK, WineD3D** are open source and may be bundled where their
  licenses allow.
</content>
