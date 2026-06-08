# steam-on-m1-wine (vendored MIT components)

Upstream: https://github.com/notpop/steam-on-m1-wine (MIT License)

Cosmos vendors and adapts the following pieces:

| Path | Upstream source | Purpose |
|------|-----------------|--------|
| `wrapper/` | `wrapper/` | `steamwebhelper.exe` CEF flag injector for Steam on Wine/DXMT |
| `assets/japanese-fonts.reg` | `scripts/assets/japanese-fonts.reg` | Wine font substitution for CJK Steam UI |
| `assets/virtual-desktop.reg` | `scripts/assets/virtual-desktop.reg` | Optional Wine virtual desktop defaults |

Integration code lives in `scripts/lib/steam_lib.sh` and
`scripts/install_steamwebhelper_wrapper.command`.

Do not copy GPL projects into this tree. See `docs/LICENSING.md`.
