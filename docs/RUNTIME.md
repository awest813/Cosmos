# Cosmos Runtime (1.0 preview)

Versioned, pinned stack for Wine-on-macOS. Manifest:
`runtime/cosmos-runtime.json`.

## Pinned components

| Component | Default version | License |
| --- | --- | --- |
| Wine (Gcenx) | 11.8 | Wine upstream |
| DXMT | 0.80 (pinned); 0.81+ via Latest channel | MIT through v0.80; LGPL after |
| DXVK-macOS | 1.10.3-20230507-repack | Zlib |
| MoltenVK | 1.2.8 | Apache-2.0 |

`run.command` loads the manifest on startup unless you override versions via
environment variables.

### Gcenx Wine pin bumps

When updating `components.wine.version` in this manifest, follow
[WINE_GAP_VALIDATION.md](WINE_GAP_VALIDATION.md):

```bash
./scripts/validate_wine_gaps.sh check      # fails until validation JSON updated
./scripts/validate_wine_gaps.sh probe      # macOS: Wine #29384 synthetic test
./scripts/test_wine_gap_validation.sh
```

Tracked state: `runtime/wine-gap-validation.json`.

## Experimental DXVK auto-fetch

```bash
COSMOS_AUTO_DXVK=1 COSMOS_BACKEND=dxvk ./run.command --setup-steam
```

Downloads DXVK-macOS + MoltenVK into:

`~/Library/Application Support/Cosmos/Runtime/`

and sets `DXVK_PATH` + Vulkan ICD paths automatically.

## DXMT LGPL (adopted)

DXMT releases after v0.80 are LGPL. Cosmos **defaults to allowing LGPL DXMT**
(`COSMOS_ALLOW_LGPL=1` from `runtime/cosmos-runtime.json`). The dashboard
**Latest (LGPL)** channel tracks `components.dxmt.latest_version` in the manifest.

To refuse LGPL versions above the MIT pin (v0.80):

```bash
export COSMOS_ALLOW_LGPL=0
```

Source offers: `runtime/DXMT-SOURCE-OFFER.txt`, `runtime/WINE-SOURCE-OFFER.txt`.
See [LICENSING.md](LICENSING.md) and [LGPL_IMPACT.md](LGPL_IMPACT.md).

## Overrides

| Variable | Effect |
| --- | --- |
| `WINE_VERSION` / `WINE_URL` | Override Wine pin |
| `DXMT_VERSION` / `DXMT_URL` | Override DXMT pin |
| `COSMOS_RUNTIME_DIR` | Cache directory for auto-fetched DXVK/MoltenVK |
| `COSMOS_AUTO_DXVK` | `1` = download DXVK stack when `DXVK_PATH` unset |

## Status

```bash
./run.command --status
```

Shows manifest version and runtime cache path when loaded.

## Offline bundle (Wine + DXMT)

Stage a pinned offline tarball:

```bash
scripts/stage_offline_runtime.command
# Linux CI stub: FIXTURE=1 scripts/stage_offline_runtime.command
```

Produces `build/offline-runtime/cosmos-runtime-offline.tar.xz`. DMG builds
(`scripts/build_dmg.command`) stage this automatically and ship:

- `CosmosRuntime.tar.xz` on the disk image root
- `Contents/Resources/runtime/cosmos-runtime-offline.tar.xz` inside Cosmos.app

`run.command` extracts the bundle before network download when
`COSMOS_USE_BUNDLED_RUNTIME=1` (default). Disable with `COSMOS_USE_BUNDLED_RUNTIME=0`.

Override tarball path: `COSMOS_OFFLINE_RUNTIME_TARBALL=/path/to/cosmos-runtime-offline.tar.xz`

## Bundled in Cosmos.app

`scripts/build_cosmos_app.command` copies `runtime/` (manifest + NOTICE) and,
when present, the offline tarball into the app Resources folder.
