# Highball

[Highball](https://github.com/gauthierpiarrette/highball) is a GPL-3.0 Apple
Silicon launcher. Cosmos vendors that source, plus the
[highball-db](https://github.com/gauthierpiarrette/highball-db) recipes and
compatibility database it reads. Curated recipes/data are CC0; derived predictions
are ODbL and anti-cheat data retains its MIT notice.

| Tree | License | Upstream commit |
| --- | --- | --- |
| `third_party/highball` | GPL-3.0 | `bbada878d142521a3267f0818a09cd62111b5789` |
| `third_party/highball-db` | CC0-1.0 curated data/recipes; ODbL-1.0 `db/derived`; MIT-derived anti-cheat data | `2b5c876308a39268189b12f391d07c34c5fb7c3e` |

The Swift app, CLI, engine manifests, patches, tests, and scripts are the
upstream files. Highball stays its own app. The dashboard lists it with Vermut
under **Highball and Vermut**, where you can open this guide, show the folder,
and build. Building from the dashboard uses a checkout of this project. An
installed Cosmos.app opens this guide. The Highball source stays in the project
folder. Build on macOS 14 or later:

```bash
scripts/build_highball.command
```

That runs `swift build -c release` in `third_party/highball`. The CLI is
`third_party/highball/.build/release/highball`. The app is
`third_party/highball/.build/release/HighballApp`. Recipes resolve to
`third_party/highball-db` when you run commands from the Highball directory.

```bash
cd third_party/highball
.build/release/highball engine install spike/engine-manifest.json
.build/release/highball bottle create play --recipe steam
```

## Left out

`spike/d3dmetal-license.txt` is Apple's Game Porting Toolkit license. It is not
part of Highball's GPL grant, and Cosmos does not redistribute it. The app
already says to read `License.pdf` from the
[Gcenx game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit)
release before accepting D3DMetal. Engine manifests still name that license id.
No Wine, DXMT, MoltenVK, or D3DMetal binaries are in the vendor tree. Install
downloads them and checks the published SHA-256.

## What this adds

Highball is the piece Cosmos did not have: pinned engines (Gcenx, Sikarugir,
and a Wine 11 tree built from published CrossOver sources), per-game renderer
choices from an open database, Steam and Epic setup, 32-bit WoW64, msync, and
a native library UI. Play still asks you to accept Apple's license before
D3DMetal is turned on.
