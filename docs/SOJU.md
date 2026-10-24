# Store launch fixes

[Soju](https://github.com/BCD1210/soju) is a GPL-3.0 launcher for Battle.net, Steam, Epic, and GOG on Apple Silicon. Cosmos does not include Soju's source, and it does not build or ship CodeWeavers' Wine. The behaviors below are Cosmos's own implementation of the launch facts Soju documented.

Apple's Game Porting Toolkit is still a separate download. Games and store clients stay with their publishers.

## AVX

Diablo II: Resurrected's loader asks Rosetta for AVX. Without `ROSETTA_ADVERTISE_AVX=1` the process sits at about 86 MB and 0% CPU, before graphics start.

`COSMOS_ROSETTA_AVX` chooses when Cosmos sets that variable, unless you already exported `ROSETTA_ADVERTISE_AVX`:

| Value | Behavior |
| --- | --- |
| `auto` | Default. Set it on Apple Silicon (`arm64`). |
| `on` | Set it on every launch. |
| `off` | Leave Rosetta's CPU report unchanged. |

## Login page

Battle.net's login page checks that a written page in `libcef.dll` is a normal writable page. Wine reports a copy-on-write page instead, and the page stays blank. `WINE_SIMULATE_WRITECOPY=1` is the switch Wine already has for that check.

| `COSMOS_WINE_WRITECOPY` | Behavior |
| --- | --- |
| `auto` | Default. On for Battle.net, Epic, and GOG. Steam is unchanged. |
| `on` | On for every launch. |
| `off` | Leave the variable unset. |

An explicit `WINE_SIMULATE_WRITECOPY` value always wins. Battle.net is detected from `BATTLENET_LAUNCHER_EXE`, Epic from `LEGENDARY_APP_NAME`, and any of the three from `COSMOS_STORE=battlenet|epic|gog`.

## D3DMetal layout

D3DMetal engages when three pieces are installed into Wine's library folder:

1. `lib/external/libd3dshared.dylib` and `lib/external/D3DMetal.framework`
2. Apple's `d3d11.dll`, `d3d12.dll`, and `dxgi.dll` in `lib/wine/x86_64-windows/` (optional extras: `d3d10.dll`, `atidxx64.dll`, `nvapi64.dll`, `nvngx.dll`)
3. One `lib/wine/x86_64-unix/<name>.so` per shim, as a symlink to `../../external/libd3dshared.dylib`

A real file in place of that symlink breaks the Metal loader. Copying only the DLLs into the prefix leaves Wine on its own Direct3D path.

Cosmos keeps a backup named `<name>.dll.cosmos-bak` before replacing a library Wine already had. Undo restores those backups, removes shims that were added, and removes the symlinks.

```bash
./run.command --gptk-layout-status
./run.command --gptk-layout
./run.command --gptk-layout-revert
```

Point `GPTK_PATH` at the toolkit you downloaded from Apple, or set `COSMOS_GPTK_PAYLOAD` to the folder that contains `libd3dshared.dylib` and `D3DMetal.framework`. The install is refused when `d3d11.dll`, `d3d12.dll`, or `dxgi.dll` is missing, and nothing is changed in that case.

When the layout is present and the D3DMetal backend is selected, Cosmos points `CX_APPLEGPTK_LIBD3DSHARED_PATH` at `libd3dshared.dylib` and adds Wine's `lib` directory to `DYLD_FALLBACK_LIBRARY_PATH`.

## Launch path

macOS removes `DYLD_*` variables when a platform binary such as `nohup` or `arch` starts the next program. Cosmos starts Wine directly and detaches that process itself, so the Metal libraries still reach the game.

## Battle.net signature

The Battle.net agent checks the signature of `Battle.net.exe` using a relative path from the versioned folder it was started in (`Battle.net.12345`). Error `BLZBNTBNA00000005` means that copy is missing or stale. Before the agent starts, and from the dashboard, Cosmos copies the signed `Battle.net.exe` into each of those folders when the bytes differ.

```bash
./run.command --battlenet-seed
```

## License boundary

Soju is GPL-3.0. Combining its scripts with Cosmos would pull Cosmos under GPL-3.0. Cosmos stays LGPL-3.0-or-later. Do not copy Soju's source, hash lists, or CodeWeavers engine into this repository. D3DMetal remains a personal download from Apple.
