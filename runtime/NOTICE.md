# Cosmos Runtime — Third-Party Notices

**Cosmos application:** LGPL-3.0-or-later (see `LICENSE`).

Cosmos may download or bundle the following runtime components. See
`docs/LICENSING.md` and `docs/LGPL_IMPACT.md`.

## LGPL components (copyleft applies when redistributing binaries)

| Component | Version (pinned) | License | Source offer |
| --- | --- | --- | --- |
| **Wine** (Gcenx macOS builds) | see `cosmos-runtime.json` | **LGPL-2.1+** | `WINE-SOURCE-OFFER.txt` |
| **DXMT** (Latest channel only) | 0.81+ when enabled | **LGPL-3.0+** | `DXMT-SOURCE-OFFER.txt` |
| **Winetricks** (external) | user-installed | **LGPL-2.1** | `WINETRICKS-NOTICE.txt` |

DXMT **0.80** (default Pinned channel) is **MIT** — no LGPL obligations for that
version. Set `COSMOS_ALLOW_LGPL=0` to refuse LGPL DXMT above 0.80.

## Permissive components

| Component | Version (pinned) | License |
| --- | --- | --- |
| DXMT (Pinned channel) | 0.80 | MIT |
| DXVK-macOS (Gcenx) | see manifest | Zlib |
| MoltenVK (Khronos) | see manifest | Apache-2.0 |

## Not bundled

| Component | Notes |
| --- | --- |
| Apple Game Porting Toolkit (D3DMetal) | User supplies `GPTK_PATH` — proprietary |
| CrossOver application | Proprietary — hints only via CosmosDB |
| CodeWeavers Wine source | LGPL reference — see `CODEWEAVERS-WINE-SOURCE.txt` |

Winetricks is invoked by `repair.command` when the user has installed it
(`brew install winetricks`). Cosmos does not bundle winetricks.
