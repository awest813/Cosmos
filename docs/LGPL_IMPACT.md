# LGPL and Cosmos

Cosmos is licensed under the **GNU Lesser General Public License v3.0 or later
(LGPL-3.0+)**. See [LICENSE](../LICENSE).

This aligns the project with its core **LGPL Wine** runtime and optional **LGPL
DXMT** channel, while keeping vendored MIT third-party trees under their original
licenses.

## What LGPL means for Cosmos

| Audience | Impact |
| --- | --- |
| **Users** | Run, study, and share Cosmos freely. No fee for personal use. |
| **Modifiers** | If you **distribute** a modified Cosmos, provide corresponding source under LGPL-3.0+. |
| **Proprietary apps** | LGPL allows linking proprietary programs to LGPL **libraries** under specific rules; Cosmos as a whole is an LGPL application — consult counsel before embedding in closed products. |

Cosmos is **not** MIT. Third-party MIT components in `third_party/` remain MIT
with their LICENSE files preserved.

## Runtime stack (unchanged obligations)

| Component | License | Notes |
| --- | --- | --- |
| **Cosmos** (this repo) | **LGPL-3.0+** | Scripts, SwiftUI app, recipes, profiles |
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

This is separate from Cosmos's own LGPL license — it gates an **optional MIT vs
LGPL third-party** graphics library.

## What LGPL Cosmos still cannot absorb

| Upstream | License | Why |
| --- | --- | --- |
| **Whisky**, **Heroic** | GPL-3.0 | GPL-3 code cannot be combined into an LGPL-3 work without the combined work becoming GPL-3 |
| **protonfixes / umu-protonfixes** | GPL-3.0 | Port ideas to YAML/recipes — do not copy Python scripts |
| **CrossOver app** | Proprietary | Hints only via CosmosDB |

LGPL Cosmos **can** more directly integrate other **LGPL** runtime pieces (Wine,
DXMT Latest, winetricks if bundled in future) without the old MIT/LGPL split
friction.

## Distribution checklist

When shipping Cosmos or an offline runtime bundle:

- [ ] Include [LICENSE](../LICENSE) (LGPL-3.0+)
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
