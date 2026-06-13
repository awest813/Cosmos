# Wine gap validation (Gcenx pin bumps)

Cosmos tracks known Wine-on-macOS gaps against the **Gcenx Wine pin** in
`runtime/cosmos-runtime.json`. The highest-priority gap is
[Wine #29384](https://bugs.winehq.org/show_bug.cgi?id=29384): **VirtualProtect**
must preserve copy-on-write patches to PE `.text` pages (SKSE, F4SE, ASI loaders).

State lives in `runtime/wine-gap-validation.json`. CI fails if the manifest Wine
version and validation pin diverge — forcing a re-validation whenever Gcenx bumps.

## Quick reference

```bash
# CI / after any runtime manifest edit
./scripts/validate_wine_gaps.sh check

# Human summary
./scripts/validate_wine_gaps.sh status

# macOS: synthetic PE probe + manual checklist
./scripts/validate_wine_gaps.sh manual-checklist
./scripts/fixtures/wine_gap/build_cow_probe.sh
./scripts/validate_wine_gaps.sh probe

# Record results after manual testing
./scripts/validate_wine_gaps.sh record wine_29384_virtualprotect_cow fail "Gcenx 11.8 probe exit 2"
./scripts/validate_wine_gaps.sh record-test wine_29384_virtualprotect_cow synthetic_cow_probe fail
```

## When bumping `runtime/cosmos-runtime.json` wine.version

1. **Edit the manifest** — update `components.wine.version`, `url`, and
   `runtime/WINE-SOURCE-OFFER.txt` if needed.
2. **Run sync check** (will fail until step 3):
   ```bash
   ./scripts/validate_wine_gaps.sh check
   ```
3. **Update** `runtime/wine-gap-validation.json`:
   - Set `pinned_wine_version` to the new Gcenx version
   - Set `gcenx_release` URL to the matching GitHub release tag
   - Set `gaps.wine_29384_virtualprotect_cow.status` to **`untested`**
   - Reset all `tests.*.status` under that gap to **`untested`**
   - Update `last_reviewed` after validation completes
4. **macOS validation** (requires Rosetta on Apple Silicon):
   ```bash
   ./run.command --setup-steam    # or extract offline Gcenx bundle
   ./scripts/fixtures/wine_gap/build_cow_probe.sh   # brew install mingw-w64
   ./scripts/validate_wine_gaps.sh probe
   ```
   | Probe exit | Meaning |
   |------------|---------|
   | `0` | COW preserved — #29384 likely fixed; set gap status to **`pass`** |
   | `2` | COW lost — bug still present; keep **`fail`** |
   | `1` | Probe error (permissions/env) — investigate, leave **`untested`** |
5. **Manual game tests** (see checklist):
   ```bash
   ./scripts/validate_wine_gaps.sh manual-checklist
   ```
   - Skyrim SE + SKSE (`steam-489830-skyrim-se.yaml`)
   - Fallout 4 + F4SE (`steam-377160-fallout-4.yaml`)
   - Steam CEF (`./run.command --steam`)
6. **Record and commit** validation JSON with manifest bump in the same PR.
7. **CI**: `./scripts/test_wine_gap_validation.sh` runs in `scripts/test_all.sh`.

Set `COSMOS_ENFORCE_WINE_GAP=1` to fail `check` when #29384 status is `untested`
(use on release branches).

## Synthetic probe (`cow_probe.exe`)

`scripts/fixtures/wine_gap/cow_probe.c` builds a minimal PE that:

1. Patches the first byte of a function in its own `.text` section
2. Calls `VirtualProtect` to restore `PAGE_EXECUTE_READ`
3. Re-reads the byte — if reverted, Wine reloaded file-backed pages (**#29384**)

This mirrors the failure mode described in
[Cauldron patch 0001](https://github.com/cashcon57/cauldron/blob/main/patches/cauldron/0001-ntdll-Preserve-private-pages-on-VirtualProtect.patch)
and [CAULDRON_WINE_PATCHES.md](CAULDRON_WINE_PATCHES.md).

Gcenx Wine is **x86_64**; on Apple Silicon run under Rosetta:

```bash
arch -x86_64 ~/wine-11.8/Wine\ Devel.app/Contents/Resources/wine/bin/wine64 cow_probe.exe
```

## Validation JSON schema

| Field | Purpose |
| --- | --- |
| `pinned_wine_version` | Must match `cosmos-runtime.json` `components.wine.version` |
| `gaps.wine_29384_virtualprotect_cow.status` | `pass` \| `fail` \| `untested` |
| `tests.synthetic_cow_probe` | Automated probe result |
| `tests.skse64_loader` / `f4se_loader` | Manual mod-loader smoke tests |
| `tests.steamwebhelper_cef` | Steam UI regression guard |

Other gaps (`cauldron_0004`, `macdrv_flicker`) are tracked as **`mitigated`**
via Cosmos workarounds; re-check on major Wine bumps.

## Related docs

- [ROADMAP.md](ROADMAP.md) — §1.0 tracked Wine gaps
- [CAULDRON_WINE_PATCHES.md](CAULDRON_WINE_PATCHES.md) — patch audit context
- [RUNTIME.md](RUNTIME.md) — Gcenx pin and offline bundle
