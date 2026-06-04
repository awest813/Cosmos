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

- Cosmos currently pins **DXMT v0.74** in `run.command` (`DXMT_VERSION`).
- Releases **after v0.80** moved from MIT to **LGPL**. Before upgrading:
  - Read [3Shain/dxmt licensing discussion](https://github.com/3Shain/dxmt/releases).
  - If you ship DXMT inside Cosmos artifacts, comply with LGPL (source offer,
    license notice) or stay on the last MIT release.
- Download URLs: `https://github.com/3Shain/dxmt/releases`

## Wine (Gcenx macOS builds)

- Downloaded at runtime from Gcenx release tarballs; verify license on each
  release artifact before bundling offline installers.

## Winetricks (repair engine)

- **LGPL-2.1** — Cosmos **does not vendor** winetricks.
- `repair.command` shells out to the user's `winetricks` binary (`brew install winetricks`).
- Recipe IDs in `recipes/dependencies/` map to winetricks verbs only.

## ProtonDB Community API

- MIT client data source: [Trsnaqe/protondb-community-api](https://github.com/Trsnaqe/protondb-community-api).
- `cosmosdb.command` uses a public instance by default; override with
  `COSMOS_PROTONDB_API_URL`. ProtonDB data is community-submitted and unofficial.

## Reference launchers (GPL vs MIT)

| Project | License | Use in Cosmos |
| --- | --- | --- |
| [Whisky](https://github.com/Whisky-App/Whisky) | GPL-3 | UX patterns only — do not copy Swift source into MIT Cosmos |
| [Heroic](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher) | GPL-3 | Architecture reference only |
| [macos-wine-steam / Merlot](https://github.com/ByMedion/macos-wine-steam) | MIT | Direct lineage; safe to compare scripts |
| [find-steam-app](https://github.com/Ciberusps/find-steam-app) | MIT | Optional detection cross-check |

See also [OPEN_SOURCE_INTEGRATIONS.md](OPEN_SOURCE_INTEGRATIONS.md).
