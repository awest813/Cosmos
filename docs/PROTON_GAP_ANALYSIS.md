# Cosmos vs. Steam Proton — Gap Analysis

This document compares **Cosmos** against **Proton / Steam Play** (Valve's Windows
compatibility layer for Linux) and lists what is still missing for Cosmos to be,
in spirit, "the macOS version of Proton." It is a planning companion to
[ROADMAP.md](ROADMAP.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

> TL;DR — The *skeleton* is already Proton-shaped (per-game profiles, a backend
> selector, a repair engine, a compatibility DB, `.app` generation, isolated
> bottles). The gaps are **depth, distribution polish, and a few hard blockers**
> (anti-cheat, a turnkey D3D12 path, and the Apple-Silicon CPU-translation tax).

## The architectural gap everything flows from

**Proton is a compatibility tool *inside* the native Linux Steam client.** The
user clicks **Play**, Steam selects the compatibility tool, and the game runs in
an automatically-managed per-title prefix (`compatdata`). There is no separate
app to install or manage.

**Cosmos runs the *Windows* Steam client under Wine**, because Valve ships no
native modern Steam + Proton for macOS. This is the only viable approach, but it
means Cosmos cannot inherit Proton's "it's just Steam" seamlessness — it has to
rebuild the surrounding experience (library, launch, settings, updates) itself.

A second structural gap: **Proton on x86-64 Linux translates only the GPU**
(D3D→Vulkan). **Cosmos translates the GPU *and* the CPU** (x86→ARM via Rosetta 2)
on Apple Silicon. That double-translation tax is inherent to the platform and
largely unclosable; it caps the performance ceiling relative to Proton-on-Linux.

## Side-by-side

| Capability | Proton / Steam Play | Cosmos today |
| --- | --- | --- |
| Integration model | Built into native Steam; click **Play** | Windows Steam under Wine; Cosmos dashboard + generated `.app`s |
| CPU | Native x86-64 (no CPU translation) | x86→ARM via Rosetta 2 (extra tax) |
| D3D9/10/11 | DXVK → Vulkan | DXMT → Metal (default, no setup) |
| D3D12 | VKD3D-Proton → Vulkan | D3DMetal/GPTK (manual Apple download) or experimental VKD3D |
| Runtime | One bundled, versioned stack per Proton release | Pieces downloaded separately (bundled "Cosmos Runtime" is the 1.0 goal) |
| Anti-cheat | EAC + BattlEye runtime support | None (status label "Blocked" only) |
| Thread sync | esync / fsync | None |
| Shader pre-caching | Fossilize (hides first-run stutter) | None |
| Controllers | Steam Input (remap, most pads) | None (Console mode is unbuilt) |
| Steam Overlay | Works | Deliberately disabled (destabilizes Wine-on-Metal) |
| Cloud saves / achievements | Works | Works (the real Windows Steam client runs) |
| Compatibility data | ProtonDB + Deck Verified badges at point-of-use | 20 curated profiles + CosmosDB lookups; badges/breadth WIP |
| Install | Toggle a checkbox | Download ZIP → compile from source → clear Gatekeeper |
| Updates | Silent, via Steam | Manual re-download / rebuild |

## Gaps ranked by impact

1. **Anti-cheat (largest "Blocked" catalog).** Proton ships EAC + BattlEye
   support; Cosmos has none, and on macOS this is near-impossible without vendor
   cooperation. The right move is **loud, honest messaging** so users aren't
   surprised — not a label buried in a status enum.
2. **Turnkey D3D12.** The no-setup default (DXMT) tops out around D3D11. D3D12
   needs D3DMetal/GPTK, which is a **manual, non-redistributable Apple download**,
   or experimental VKD3D. Gap: a one-click D3D12 path.
3. **Distribution & install friction.** No signed/notarized, double-click
   installer. Today: unzip → run `build_cosmos_app.command` → compile SwiftUI →
   clear Gatekeeper → Terminal for `sudo`. This is the biggest *ease-of-use* gap
   and the **most tractable** — a drag-to-`/Applications` `Cosmos.dmg` removes the
   compile-from-source step. (See `scripts/build_dmg.command`.)
4. **No bundled, versioned runtime.** Proton ships one tested stack; Cosmos
   downloads Wine + DXMT + … separately, so compatibility is less reproducible.
   This is the explicit **1.0 "Cosmos Runtime"** goal.
5. **Performance primitives.** No `esync`/`fsync` thread-sync acceleration and no
   shader pre-caching, so CPU-bound titles and first-run stutter are worse than
   on Proton.
6. **Controller support.** None today. Proton's Steam Input "just works" for most
   pads; Cosmos's controller-driven Console mode is on the roadmap but unbuilt.
7. **Steam Overlay / in-game features.** Disabled on purpose (Shift-Tab, overlay
   purchases, FPS counter unavailable). Cloud saves and achievements still work.
8. **Compatibility breadth & ratings UI.** 20 hand-tested profiles vs. Proton's
   thousands; CosmosDB lookups exist, but community reports, status badges, and
   one-click profile updates surfaced *in the library before launch* are open
   0.7 items.
9. **Auto-update.** No self-update for the app or runtime.
10. **AVX/AVX-512 & CPU edge cases.** Rosetta covers most x86, but titles needing
    AVX-512 or specific CPU features still fail; native-x86 Proton does not hit
    this.

## What already maps to Proton

The bones are genuinely Proton-shaped, which narrows the gap:

| Proton concept | Cosmos equivalent |
| --- | --- |
| Per-title fixes (protonfixes) | Per-game YAML profiles + `overrides/<appid>.env` |
| DXVK / VKD3D / wined3d choice | `COSMOS_BACKEND` selector (dxmt / d3dmetal / dxvk / wined3d) |
| ProtonDB | CosmosDB + ProtonDB/AppleGamingWiki/MacGamingDB lookups |
| `compatdata` per-game prefixes | Bottles (isolated Wine prefixes) |
| Steam desktop integration | `.app` generation into `/Applications/Cosmos Apps` |
| Proton versions (Experimental, etc.) | Planned "Cosmos Runtime" versioning (1.0) |

## Closing the gaps — suggested order

Prioritized for **impact × tractability on macOS**:

- **(a) Signed/notarized double-click installer.** Most self-contained, biggest
  ease-of-use win. First step shipped: `scripts/build_dmg.command` produces a
  drag-to-`/Applications` DMG (ad-hoc signed); a Developer ID signature +
  notarization is the follow-up.
- **(b) Turnkey D3D12** via a guided GPTK setup or a maturing VKD3D path.
- **(c) Performance:** shader caching + esync/fsync where Wine-on-macOS allows.
- **(d) Surface compatibility badges in the library** (CosmosDB 0.7) so users see
  "Playable / Broken / Blocked" before launching or buying.
- **(e) Honest anti-cheat / blocked messaging** at detect- and launch-time.
  First step shipped: a pre-launch compatibility heads-up
  (`run.command` `compat_preflight` / `--compat-check <appid>`) warns when a
  game's curated profile is `broken`/`blocked`, with Destiny 2 as a real
  anti-cheat example. Surfacing the same badge in the dashboard library is the
  follow-up.

These do not make Cosmos *equal* to Proton — the CPU-translation tax and
anti-cheat blockers are structural — but they close the gaps that users actually
feel first.
</content>
