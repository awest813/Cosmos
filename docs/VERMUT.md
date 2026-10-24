# Vermut 1.2.0

[Vermut](https://github.com/Contessafry/Vermut) is an MIT Apple Silicon
launcher for Windows game stores. Cosmos vendors the **v1.2.0** source at
`third_party/vermut`.

| | |
| --- | --- |
| Tag | [v1.2.0](https://github.com/Contessafry/Vermut/releases/tag/v1.2.0) |
| Commit | `3ad9649ee0ff88812052af3672992dfa354c1892` |
| License | MIT. Copyright (c) 2026 Vermut Contributors. See `third_party/vermut/LICENSE` |

The Swift app, core library, tests, brand assets, and scripts are the
upstream files. Cosmos’s own dashboard is unchanged. Build Vermut on macOS 14
or later:

```bash
scripts/build_vermut.command
```

That runs `swift build -c release` in `third_party/vermut`.

## What 1.2.0 adds

- In-app update check with Stable and Beta channels
- Several DXMT versions, default v0.80
- Gcenx Wine Staging and Devel 11.18, downloaded when needed
- D3DMetal detection for a toolkit the user installed
- Per-game engine, graphics backend, DXMT version, and log level
- Extra Wine bottles
- Steam covers in the library
- Remove Vermut Data, then trash the app yourself
- Steam setup that quits without touching a native Steam install

## Left out

The release disk image `Vermut-1.2.0.dmg` is not in this tree. Wine, DXMT,
DXVK, MoltenVK, Legendary, and D3DMetal are not bundled. Vermut downloads the
open-source pieces at runtime and looks for a D3DMetal install you already
have. Their licenses are listed in `third_party/vermut/THIRD_PARTY.md`.
