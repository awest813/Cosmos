# Apple Silicon Ports

A **port** is a Windows program that opens like a Mac app. Cosmos bottles and
the game library are the Whisky / Lutris side (manage an environment, install,
fix, launch). Ports are the [Sikarugir](https://github.com/Sikarugir-App/Sikarugir)
side — the model mirrored in [awest813/cosmosNEW](https://github.com/awest813/cosmosNEW):
a double-clickable wrapper, an explicit DirectX stack, and a hard rule that
Apple's D3DMetal is not part of anything you hand to someone else.

Cosmos does not bundle Sikarugir, Wineskin, or D3DMetal.

## What you get

| | Bottles | Ports |
| --- | --- | --- |
| Job | Isolated Windows environment | One program, one Mac app |
| Where it lives | `~/Library/Application Support/Cosmos/Bottles/` | Definition in `.../Cosmos/Ports/`, app in `~/Applications/Cosmos Ports/` |
| Graphics | One backend for the whole bottle | Sikarugir-style switches that stay on together. DXMT and SpockD3D9 launch side by side |
| Machines | Apple Silicon and Intel | **Apple Silicon only**, macOS **14.6+** |

The dashboard **Ports** tab (⌘5, under Advanced) creates, opens, and builds ports
after Steam setup. The same actions work from `port.command` before you care
about the menu.

## Graphics stack

Defaults match Sikarugir on Apple Silicon:

| Renderer | Default | DirectX | Cosmos launch backend |
| --- | --- | --- | --- |
| DXMT | on | 10 / 11 → Metal | Stays on. The launch backend is `spockd3d9` when SpockD3D9 is also on |
| SpockD3D9 | on | 8 / 9 → Vulkan | `spockd3d9`. The 32-bit DLL goes in `syswow64`, the 64-bit DLL in `system32` |
| CNC-DDRAW | on | classic DirectDraw | Stays on the primary backend. Set `CNC_DDRAW_PATH` to a folder with `ddraw.dll` |
| WineD3D | on | 7 and below | `wined3d` when it is the only modern path |
| DXVK | off | 10 / 11 → Vulkan | `dxvk` |
| D3DMetal | off | 11 / 12 → Metal | `d3dmetal`, **personal ports only** |

D3DMetal needs your own Game Porting Toolkit (`--gptk-path` or `GPTK_PATH`).
Cosmos never downloads it. A port with distribution `share` cannot turn
D3DMetal on, and the built app does not record a GPTK path. `run.command`
also refuses a shared port whose resolved backend is `d3dmetal`.

## Commands

```bash
./port.command create --name "Notepad" --exe /path/to/notepad.exe
./port.command show notepad
./port.command build notepad
./port.command launch notepad
./port.command delete notepad
```

Useful options on `create`: `--bottle`, `--distribution personal|share`,
`--windows`, `--retina`, `--args`, `--program-arch win64|win32`, `--dxmt`, `--d9vk`, `--cnc-ddraw`, `--wined3d`,
`--dxvk`, `--d3dmetal`, `--cnc-ddraw-path`, `--gptk-path`.

`build` writes `~/Applications/Cosmos Ports/<Name>.app`. The app's launcher
checks for arm64, then runs Cosmos `run.command --game` with `COSMOS_SKIP_STEAM=1`
so a non-Steam program does not wait on Steam. Pass `--bottle` when the program
should use an isolated prefix.

A 32-bit program (`--program-arch win32`) still uses the 64-bit prefix. That is
the Apple Silicon layout Sikarugir uses: 32-bit code runs through WoW64, and
SpockD3D9's 32-bit `d3d9.dll` is the DirectX 9 piece. If that DLL has not been
built, DirectX 9 stays on WineD3D. A bottle can instead be 64-bit only
(`--arch win64`) or 32-bit only (`--arch win32`).

Tests that create or build a port on Linux or an Intel Mac set
`COSMOS_PORT_SKIP_ARCH=1`. That flag does not make the port run there.
