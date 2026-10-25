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

The dashboard **Ports** tab (⌘3, on the main tab bar) creates, edits, opens, and builds ports
from the first launch. Steam setup is optional. The same actions work from
`port.command`.

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
./port.command update notepad --windows win7 --args '--windowed'
./port.command build notepad
./port.command launch notepad
./port.command delete notepad
```

Useful options on `create`: `--bottle`, `--distribution personal|share`,
`--windows`, `--retina`, `--args`, `--program-arch win64|win32`, `--dxmt`, `--d9vk`, `--cnc-ddraw`, `--wined3d`,
`--dxvk`, `--d3dmetal`, `--cnc-ddraw-path`, `--gptk-path`.

Select a port and choose **Edit** to change its executable, environment, Windows
version, arguments or graphics. Saving preserves its ID and installed files.
Failed validation/save keeps the previous definition; the form stays open for
correction. Existing Mac apps keep their previous settings until **Make Mac App**
is run again. Renaming a port does not remove an app built under its old name.

`update <slug>` accepts the `create` options except `--slug`; omitted values keep
their current settings. Use `--args ''`, `--bottle ''`, `--cnc-ddraw-path ''` or
`--gptk-path ''` to clear a value. Selecting another existing EXE detects its
architecture unless explicitly overridden; conflicting bitness is rejected.
Definitions are staged and replaced atomically, retaining extension metadata and
the previous built-app location. Updating a definition does not run Wine.

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

## Launch and setup details

The program picker detects x86/x64 PE executable headers and selects 32-bit or
64-bit automatically. CLI creation also detects an existing executable when
`--program-arch` is omitted and rejects a conflicting explicit choice. For
missing or prefix-relative paths, choose the program architecture yourself.
These header checks do not establish runtime or graphics compatibility.

Ports require Apple Silicon and macOS 14.6 or later. The dashboard explains an
unsupported host before enabling Create/Open/Make Mac App, while existing
definitions remain browsable. CLI and generated apps enforce the same minimum;
an Apple Silicon Mac running a Rosetta Terminal is recognized correctly.

If creation fails, the form retains its fields and shows the error so you can
correct it and retry. It closes only after creation succeeds.

Use **Graphics Downloads** to get Spock and MoltenVK. On a fresh installation,
ports that have WineD3D enabled can open before Spock is built: DirectX 9 uses
WineD3D and DXMT continues to handle DirectX 10/11. This fallback does not fetch
MoltenVK. An explicitly configured invalid Spock folder still needs correction.
If Rosetta is missing, the port's action reads **Install Rosetta 2** and opens
the normal installation in Terminal; open the port after that completes.

Both dashboard/CLI launches and generated apps pass the saved program architecture
to the graphics setup. Launch arguments support quoted values and empty arguments:
`--save "folder with spaces/save.dat" --label ""`. Wildcards and shell variables
stay literal; arguments are parsed as data and never executed as shell commands.
Malformed quotes stop the launch with an error. Parsing nonempty arguments requires
Python 3, already used by the Cosmos helper scripts.

When a selected program's Spock architecture is unavailable, the launch forces
WineD3D's builtin D3D9 DLL, preserving DXMT for DirectX 10/11. An old native DLL
left in the prefix by another backend cannot silently override that fallback.
For a launch without a known program architecture, both Spock DLLs are required
to prefer native D3D9. Build both from Graphics settings to cover Steam games.

The installer respects an existing win32 prefix's registry marker rather than a
changed creation preference. A win32 preference cannot replace a DLL in an
existing win64 prefix; select the matching layout or create another environment.

The Ports screen uses `COSMOS_PORTS_DIR`, or `COSMOS_SUPPORT_DIR/Ports`, matching
the CLI. Launch, build, and creation wait while a Terminal operation is pending.
See [release readiness](RELEASE_READINESS.md) for the current validation limits.
