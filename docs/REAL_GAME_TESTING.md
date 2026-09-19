# Real-game testing with Cosmos

A build, a valid DLL, and a successful launch request are not gameplay results. Record the observed backend and complete the same test sequence for each comparison.

## Current machine audit — September 7, 2026

Apple Silicon, macOS 26.5.1. No default initialized Wine prefix, `~/wine-*` runtime, default SpockD3D9 DLL directory, or Homebrew MoltenVK library was found. Meson, Ninja, mingw-w64 compilers, and glslangValidator were not on PATH. Custom runtime locations may exist; these checks do not search the entire disk. No real Windows game was launched in this audit.

## Prepare a controlled comparison

1. Choose an owned game and record its version, store, executable, and architecture. For a D3D9 test, confirm the game is actually using D3D9; title age is not proof.
2. Start with Recommended or WineD3D as a baseline. Use a dedicated named Windows environment for experiments and preserve your saves. A comparison environment needs the same game version, resolution, settings, and save/scene.
3. For SpockD3D9, use the **Windows PE** build. The native macOS `libdxvk_d3d9.dylib` is not a drop-in Wine DLL. Build tools are listed in `scripts/build-pe-d3d9.sh --help` and [the upstream instructions](https://github.com/awest813/SpockD3D9#experimental-windows-pe-d3d9dll-optional).
4. In Launch → Steam & Graphics Settings → SpockD3D9, choose the DLL folder and Validate. Check 32-bit/64-bit availability. Select the dedicated environment before choosing **Use for Selected Environment**; the default environment is changed only by **Use for Default Environment**.
5. Install/locate the game in that environment. Quit Steam and the game before changing renderers. Keep DXMT, Wine, MoltenVK, mods, and sync settings fixed between comparisons unless that component is the variable under test.

## Preflight without launching anything

From the repository, supply your actual paths:

```bash
python3 scripts/game_test_preflight.py \
  --exe '/path/to/Game.exe' \
  --prefix '/path/to/test-environment/prefix' \
  --wine '/path/to/wine' \
  --backend spockd3d9 \
  --spock-root '/path/to/spockd3d9' \
  --moltenvk '/path/to/libMoltenVK.dylib' > game-test-spock.json
```

The tool reads files only. Exit 0 means the requested structural checks passed; exit 1 means a prerequisite failed. It checks executable architecture, Wine executable presence, prefix initialization, matching Spock DLL architecture, and the supplied MoltenVK file's presence. It does **not** execute Wine, inspect Vulkan device capabilities, establish the MoltenVK library's architecture/loadability, or confirm that Steam owns/installs the title. A game-local `d3d9.dll` is flagged because it may override the prefix's copy.

For the baseline, use `--backend wined3d` or `recommended`; omit Spock/MoltenVK arguments. Both reports retain `game_result: untested` until you record observations. Keep reports locally; paths can identify your username or game locations.

## Confirm the renderer, then measure

- For one diagnostic run, enable Wine DLL-load logging (`WINEDEBUG=+loaddll`) in your test launch environment and save the output. Confirm the loaded `d3d9` is the intended native DLL, not Wine's builtin or a game-local wrapper. Compare the installed DLL hash with the preflight's source hash. Verify the Vulkan/MoltenVK path in renderer logs where available.
- Preserve the exact launch method: Steam games should still use Steam when required. Do not bypass DRM or assume direct EXE launching is equivalent.
- Disable verbose diagnostics for performance runs. Do one cold start and at least two warm repeats of the same save, route, or built-in benchmark. Record resolution, graphics preset, average FPS and 1% lows only if measured; leave unknown values blank.

## Required observations per backend

| Stage | Pass requires |
| --- | --- |
| Launch | Game window appears; expected renderer is confirmed. |
| Menu | Text/UI render correctly and mouse/keyboard/controller navigation works. |
| Gameplay | At least 15 minutes in a reproducible scene; no blocking corruption or crash. |
| Save/load | Save, reload, and verify game state. |
| Windowing | Alt-tab, resize/fullscreen transition, audio and input recovery. |
| Exit/relaunch | Quit normally, confirm exit, and launch again successfully. |
| Performance | Same settings/scene, warm/cold noted, observations separated from measured FPS. |

In Game Details & Recommended Settings, **Copy Test Details** provides a starting record and **Game Testing Guide** opens this document. Add log filenames, runtime revisions, DLL hashes, and the observed results. Use `pass`, `fail`, or `not tested` for each stage. Do not mark a title playable from menu-only success.

For a Spock issue, first compare WineD3D with the same game/settings. Restore the baseline environment to continue playing; avoid repeatedly replacing DLLs in your everyday installation. See [D3D9 evaluation](D3D9_EVALUATION.md) for the d9mt decision.
