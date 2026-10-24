# LGPL and Cosmos

Cosmos itself is **GPL-3.0-or-later**. See [LICENSE](../LICENSE). It was
LGPL-3.0-or-later; that license allows a modified version to be conveyed under
the GPL. This file still covers the **LGPL** pieces Cosmos downloads or invokes.

Vendored MIT trees in `third_party/` stay MIT.

## What the license means

| Audience | Impact |
| --- | --- |
| **Users** | Run, study, and share Cosmos freely. No fee for personal use. |
| **Modifiers** | If you **distribute** a modified Cosmos, provide corresponding source under GPL-3.0-or-later. |
| **Proprietary apps** | A GPL application is not a drop-in library for a closed product. Wine and DXMT Latest remain LGPL and keep their own obligations when you redistribute those binaries. |

Cosmos is **not** MIT. Third-party MIT components in `third_party/` remain MIT
with their LICENSE files preserved.

## Runtime stack (unchanged obligations)

| Component | License | Notes |
| --- | --- | --- |
| **Cosmos** (this repo) | **GPL-3.0-or-later** | Scripts, SwiftUI app, recipes, profiles |
| **Wine** (Gcenx) | LGPL-2.1+ | Downloaded runtime — source offer: `WINE-SOURCE-OFFER.txt` |
| **DXMT 0.80** (Pinned) | MIT | Default channel |
| **DXMT 0.81+** (Latest) | LGPL-3.0+ | `COSMOS_ALLOW_LGPL=1` (default) |
| **Winetricks** | LGPL-2.1 | External — `repair.command` shells out |
| **GPTK / D3DMetal** | Apple proprietary | User-supplied only |

## `COSMOS_ALLOW_LGPL` (DXMT channel gate)

Controls whether Cosmos downloads **LGPL DXMT** above the MIT pin (0.80):

```bash
export COSMOS_ALLOW_LGPL=0   # refuse DXMT > 0.80
export COSMOS_ALLOW_LGPL=1   # allow Latest channel (default)
```

This flag is not Cosmos's own license. It gates an **optional MIT vs LGPL
third-party** graphics library.

## What GPL still does not absorb

| Upstream | License | Why it stays out |
| --- | --- | --- |
| **CrossOver application** | Proprietary | Hints only via CosmosDB |
| **CodeWeavers Wine engine builds** | Mixed; the app around them is proprietary | Use published LGPL Wine source, or Gcenx builds. Do not ship their binaries |
| **Apple D3DMetal / GPTK** | Apple proprietary | User download only. A shared port cannot include it |
| **Sikarugir tree** | No LICENSE file in the repository | Do not copy. Ports in Cosmos are original code |
| **Whisky, Moonshine, Soju, Lutris, Heroic, protonfixes** | GPL-3.0 | May be combined. Keep copyright notices. Current Cosmos files are still original code |

## Distribution checklist

When shipping Cosmos or an offline runtime bundle:

- [ ] Include [LICENSE](../LICENSE) (GPL-3.0-or-later)
- [ ] Include `runtime/NOTICE.md`
- [ ] Include `runtime/WINE-SOURCE-OFFER.txt`
- [ ] Include `runtime/DXMT-SOURCE-OFFER.txt` if DXMT ≥0.81
- [ ] Preserve `third_party/*/LICENSE` for vendored MIT trees
- [ ] Include `docs/LICENSING.md` and this file in app Resources (app build)

`scripts/stage_offline_runtime.command` copies runtime notices into offline tarballs.
`scripts/build_cosmos_app.command` bundles `LICENSE`, `docs/LICENSING.md`, and
`docs/LGPL_IMPACT.md`.

## See also

- [LICENSING.md](LICENSING.md) — per-component policy
- [RUNTIME.md](RUNTIME.md) — manifest and offline bundle
