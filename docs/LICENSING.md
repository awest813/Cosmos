# Cosmos Licensing & Third-Party Components

Cosmos itself is [MIT licensed](../LICENSE). Bundled or downloaded runtimes have
their own terms — this document is the checklist before shipping or upgrading
dependencies.

## Apple Game Porting Toolkit (D3DMetal)

- **Do not bundle or redistribute** Apple's GPTK/D3DMetal DLLs.
- Users must install GPTK from [developer.apple.com](https://developer.apple.com/)
  and set `GPTK_PATH` (see [BACKENDS.md](BACKENDS.md)).
- Cosmos may copy user-supplied DLLs into a prefix at launch; that is user-directed
  use, not redistribution by Cosmos.

## DXMT

- Pinned in `runtime/cosmos-runtime.json` and loaded by `run.command` (`DXMT_VERSION`,
  default **0.74**).
- Releases **after v0.80** moved from MIT to **LGPL**. `run.command` and CI refuse
  `DXMT_VERSION` above the manifest pin unless `COSMOS_ALLOW_LGPL=1`.
- Before upgrading past the MIT pin:
  - Read [3Shain/dxmt licensing discussion](https://github.com/3Shain/dxmt/releases).
  - If you ship DXMT inside Cosmos artifacts, comply with LGPL (source offer,
    license notice) or stay on the last MIT release.
- Download URLs: `https://github.com/3Shain/dxmt/releases`

## Wine (Gcenx macOS builds)

- Version and URL pinned in `runtime/cosmos-runtime.json`.
- Downloaded at runtime from Gcenx release tarballs; verify license on each
  release artifact before bundling offline installers.

## DXVK-macOS (Gcenx)

- **Zlib** — experimental `dxvk` backend only.
- Pinned in `runtime/cosmos-runtime.json`; optional auto-download when
  `COSMOS_AUTO_DXVK=1` (see [RUNTIME.md](RUNTIME.md)).
- Upstream: [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS).

## MoltenVK (Khronos)

- **Apache-2.0** — Vulkan ICD for the experimental DXVK path on macOS.
- Pinned in `runtime/cosmos-runtime.json`; downloaded with `COSMOS_AUTO_DXVK=1`.
- Upstream: [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK).

## winemactricks-json

- MIT database vendored under `third_party/winemactricks-json/`.
- Upstream: [Alien4042x/winemactricks-json](https://github.com/Alien4042x/winemactricks-json).
- Imported into `recipes/fixes/` via `scripts/import_winemactricks.sh` (retain LICENSE notice).

## macos-wine-steam

- MIT presets vendored under `third_party/macos-wine-steam/`.
- Upstream: [ByMedion/macos-wine-steam](https://github.com/ByMedion/macos-wine-steam).
- Imported into `profiles/drafts/` via `scripts/import_macos_wine_steam.sh`.

## UMU database API

- GPL-3.0 data repository: [Open-Wine-Components/umu-database](https://github.com/Open-Wine-Components/umu-database).
- `cosmosdb.command lookup <appid> umu` fetches fix **metadata** at runtime only.
- Translate fix ideas into Cosmos YAML/recipes; **do not** vendor umu-protonfixes Python scripts.

## wineregdiff

- MIT optional tool for registry snapshots: [castaneai/wineregdiff](https://github.com/castaneai/wineregdiff).
- Cosmos does not bundle it; `repair.command diff-reg` shells out when installed.

## Winetricks (repair engine)

- **LGPL-2.1** — Cosmos **does not vendor** winetricks.
- `repair.command` shells out to the user's `winetricks` binary (`brew install winetricks`).
- Recipe IDs in `recipes/dependencies/` map to winetricks verbs only.

## ProtonDB Community API

- MIT client data source: [Trsnaqe/protondb-community-api](https://github.com/Trsnaqe/protondb-community-api).
- `cosmosdb.command` uses a public instance by default; override with
  `COSMOS_PROTONDB_API_URL`. ProtonDB data is community-submitted and unofficial.

## AppleGamingWiki

- Community wiki content (typically [CC BY-SA](https://creativecommons.org/licenses/by-sa/3.0/)).
- Cosmos reads via the public MediaWiki API for compatibility **hints** only; attribute
  the wiki when surfacing notes in UI. Do not bulk-republish wiki text.

## MacGamingDB

- Community compatibility and benchmark data from [macgamingdb.app](https://macgamingdb.app/).
- Cosmos uses the public read REST API (`/api/rest/games/{steamAppId}`) for hints.
- Open-source app: [neo773/macgamingdb](https://github.com/neo773/macgamingdb). Respect
  any rate limits; cache responses locally (Cosmos defaults to 24h).

## Reference launchers (GPL vs MIT)

| Project | License | Use in Cosmos |
| --- | --- | --- |
| [Whisky](https://github.com/Whisky-App/Whisky) | GPL-3 | UX patterns only — do not copy Swift source into MIT Cosmos |
| [Heroic](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher) | GPL-3 | Architecture reference only |
| [macos-wine-steam / Merlot](https://github.com/ByMedion/macos-wine-steam) | MIT | Direct lineage; safe to compare scripts |
| [find-steam-app](https://github.com/Ciberusps/find-steam-app) | MIT | Optional detection cross-check; VDF parsing patterns in `steam_lib.sh` |
| [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) | MIT | Vendored `third_party/steam-on-m1-wine/` (wrapper + assets); launch/prefix integration in `steam_lib.sh` |

See also [OPEN_SOURCE_INTEGRATIONS.md](OPEN_SOURCE_INTEGRATIONS.md).
