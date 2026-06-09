# Cosmos Runtime — Third-Party Notices

Cosmos may download or bundle the following components. See `docs/LICENSING.md`
for full policy.

| Component | Version (pinned) | License |
| --- | --- | --- |
| Wine (Gcenx macOS builds) | see `cosmos-runtime.json` | Wine upstream |
| DXMT | ≤ 0.80 (MIT pin) | MIT through v0.80; LGPL after |
| DXVK-macOS (Gcenx) | see manifest | Zlib |
| MoltenVK (Khronos) | see manifest | Apache-2.0 |

Apple Game Porting Toolkit (D3DMetal) is **not** bundled — users supply `GPTK_PATH`.

Winetricks remains an external LGPL tool invoked by `repair.command`.
