# LGPL Impact on Cosmos

Cosmos is **MIT-licensed**. Several **runtime dependencies are LGPL**, which
matters when you download, bundle, or redistribute the Cosmos Runtime, or when
you port Wine patches from CodeWeavers.

This page is the practical checklist. Legal detail per component lives in
[LICENSING.md](LICENSING.md).

## Quick summary

| Component | License | Bundled by Cosmos? | Typical impact |
| --- | --- | --- | --- |
| **Cosmos** (scripts, app) | MIT | Yes (repo / app) | No copyleft on your own MIT code |
| **Wine** (Gcenx macOS builds) | LGPL-2.1+ | Downloaded / offline bundle | Source offer required when redistributing Wine binaries |
| **DXMT ≤0.80** | MIT | Downloaded / offline bundle | Permissive — no LGPL obligations |
| **DXMT ≥0.81** | LGPL-3.0+ | Optional (Latest channel) | Source offer + `COSMOS_ALLOW_LGPL=1` (default) |
| **Winetricks** | LGPL-2.1 | **No** — external `brew` install | User's obligation when they install winetricks; Cosmos shells out |
| **CodeWeavers Wine patches** | LGPL | **No** — reference only | Only if you ship a modified Wine build derived from their source |
| **CrossOver app** | Proprietary | **No** | Hints only via CosmosDB |

**Bottom line:** Using Cosmos personally does not make your own projects LGPL.
**Redistributing** Wine or LGPL DXMT binaries (offline DMG, mirrored runtime
tarball, etc.) requires LGPL compliance notices and source offers.

## Wine (always downloaded)

Every Cosmos Steam launch uses **Wine** from Gcenx macOS builds. Wine is
**LGPL-2.1+**.

**User impact**

- You may replace the downloaded Wine build with another LGPL-compliant build.
- Cosmos talks to Wine via subprocess — no Wine source is compiled into Cosmos.

**Maintainer / distributor impact**

- Offline runtime bundles and app distributions that include Wine must ship:
  - `runtime/NOTICE.md`
  - `runtime/WINE-SOURCE-OFFER.txt`
- Pin versions in `runtime/cosmos-runtime.json` and document the Wine version in
  release notes.

Source pointers: [WINE-SOURCE-OFFER.txt](../runtime/WINE-SOURCE-OFFER.txt),
[WineHQ git](https://gitlab.winehq.org/wine/wine),
[Gcenx releases](https://github.com/Gcenx/macOS_Wine_builds/releases).

## DXMT (MIT pin vs LGPL channel)

| Channel | Version | License | How to select |
| --- | --- | --- | --- |
| **Pinned** (default) | 0.80 | MIT | `COSMOS_DXMT_CHANNEL=stable` or dashboard "Pinned" |
| **Latest** | 0.81+ | LGPL | `COSMOS_DXMT_CHANNEL=latest` or dashboard "Latest (LGPL)" |

**Opt out of LGPL DXMT entirely:**

```bash
export COSMOS_ALLOW_LGPL=0
```

`runtime_lib.sh` refuses DXMT versions above the MIT pin (`0.80`) when this is
set. The dashboard and `steam.conf` persist `COSMOS_ALLOW_LGPL`.

**Distributor impact (LGPL DXMT)**

- Include `runtime/DXMT-SOURCE-OFFER.txt` and `runtime/NOTICE.md`.
- Upstream source: [3Shain/dxmt releases](https://github.com/3Shain/dxmt/releases).

## Winetricks (repair engine)

`repair.command install-dep` runs the user's **winetricks** binary. Cosmos does
**not** vendor winetricks.

```bash
brew install winetricks
./repair.command install-dep vcrun2015
```

See [WINETRICKS-NOTICE.txt](../runtime/WINETRICKS-NOTICE.txt). Installing
winetricks is the end user's choice; Cosmos recipes only reference winetricks
verb names.

## CodeWeavers / CrossOver Wine source

CrossOver's **app** is proprietary. CodeWeavers publishes **LGPL Wine source** at
[codeweavers.com/products/source](https://www.codeweavers.com/products/source/).

Cosmos:

- Uses **Gcenx Wine**, not CrossOver binaries.
- Reads **CrossOver compatibility tiers** as community hints (CosmosDB).
- Does **not** import CrossOver or Whisky (GPL-3) application code.

If you adopt CodeWeavers Wine patches into a custom Wine build you redistribute,
treat that build as LGPL — see
[CODEWEAVERS-WINE-SOURCE.txt](../runtime/CODEWEAVERS-WINE-SOURCE.txt).

## What does *not* trigger LGPL on Cosmos

| Action | Result |
| --- | --- |
| Run Cosmos from git checkout | MIT app + LGPL runtime download — normal use |
| Write MIT Swift/bash profiles and recipes | Stays MIT |
| Read GPL protonfixes / Whisky for ideas | OK if you reimplement, not copy |
| Use GPTK from Apple (user-supplied) | Apple proprietary terms — not LGPL |
| Fetch UMU API hints at runtime | GPL data — not vendored |

## Distribution checklist (offline runtime / DMG)

Before shipping a bundle that contains Wine and/or DXMT binaries:

- [ ] `runtime/NOTICE.md` included
- [ ] `runtime/WINE-SOURCE-OFFER.txt` included
- [ ] `runtime/DXMT-SOURCE-OFFER.txt` included (if DXMT ≥0.81 or Latest channel)
- [ ] `docs/LICENSING.md` or `docs/LGPL_IMPACT.md` in app Resources (app build)
- [ ] Pinned versions recorded in `runtime/cosmos-runtime.json`
- [ ] `COSMOS_ALLOW_LGPL` default documented in release notes

`scripts/stage_offline_runtime.command` copies these notices into offline tarballs.
`scripts/build_cosmos_app.command` copies `runtime/` and `docs/LICENSING.md` into
the app bundle.

## See also

- [LICENSING.md](LICENSING.md) — per-component policy
- [RUNTIME.md](RUNTIME.md) — manifest, offline bundle, DXMT channels
- [OPEN_SOURCE_INTEGRATIONS.md](OPEN_SOURCE_INTEGRATIONS.md) — CrossOver / CodeWeavers table
