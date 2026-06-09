# CosmosDB (v0 preview)

CosmosDB is Cosmos's compatibility layer: **hints from community sources** plus
**local macOS reports** from real runs. Roadmap milestone **0.7**.

## Data sources

| Source | Role | License / terms |
| --- | --- | --- |
| [ProtonDB Community API](https://github.com/Trsnaqe/protondb-community-api) | Linux/Proton ratings by Steam App ID | MIT |
| [AppleGamingWiki](https://applegamingwiki.com/) | macOS Wine / CrossOver / Parallels tiers + notes | Community wiki (CC BY-SA); MediaWiki API |
| [MacGamingDB](https://macgamingdb.app/) | Apple Silicon FPS benchmarks, play method, translation layer | Community site; public read REST API |
| [UMU database](https://umu.openwinecomponents.org/) | Proton/umu-protonfixes fix metadata by `umu-{appid}` | GPL-3.0 data repo; **runtime API hints only** |
| Local `~/Library/Application Support/Cosmos/CosmosDB/reports/` | macOS-specific user reports | User data |

**Hint priority:** local Cosmos reports > MacGamingDB / AppleGamingWiki > ProtonDB.

ProtonDB is a **weak hint** on macOS — backends differ (DXMT/D3DMetal vs Proton).
AppleGamingWiki **Wine** rows often reflect Porting Kit / GPTK paths. MacGamingDB
**translationLayer** values map to Cosmos backends: `DXMT`, `DXVK`, `D3D_METAL`
(GPTK/D3DMetal).

## CLI (`cosmosdb.command`)

```bash
./cosmosdb.command lookup 22380                    # all sources (24h cache each)
./cosmosdb.command lookup 22380 applegamingwiki    # AGW only
./cosmosdb.command lookup 1145360 macgamingdb      # MacGamingDB only
./cosmosdb.command lookup 22380 protondb            # ProtonDB only
./cosmosdb.command lookup 1091500 umu               # UMU fix metadata (if listed)
./cosmosdb.command sync                             # copy cosmos-db/ into Application Support
./cosmosdb.command badge 22380                      # resolved badge (profile > report > community)
./cosmosdb.command badge 22380 --json
./cosmosdb.command suggest-profile 250900 --write   # YAML draft in profiles/drafts/
./cosmosdb.command report 22380 gold "Stable on M2, DXMT, win10 bottle"
./cosmosdb.command list-reports
./cosmosdb.command cache-clear                      # all cached hints
./cosmosdb.command cache-clear macgamingdb
```

Environment:

- `COSMOSDB_DIR` — override storage root
- `COSMOS_PROTONDB_API_URL` — ProtonDB API base
- `COSMOS_APPLEGAMINGWIKI_API_URL` — MediaWiki API (default `applegamingwiki.com/w/api.php`)
- `COSMOS_MACGAMINGDB_API_URL` — REST base (default `https://macgamingdb.app/api/rest`)
- `COSMOS_UMU_API_URL` — UMU API base (default `https://umu.openwinecomponents.org/umu_api.php`)
- `COSMOSDB_CACHE_TTL_SECONDS` — cache lifetime (default `86400`)
- `COSMOSDB_HTTP_USER_AGENT` — User-Agent for wiki/API requests
- `COSMOS_COMMUNITY_DB_URL` — optional remote `cosmos-db` base for `sync`

## Community database (`cosmosdb-community-v0`)

Git-hosted entries under `cosmos-db/games/<appid>.json`. Synced to:

`~/Library/Application Support/Cosmos/CosmosDB/community/games/`

```json
{
  "schema": "cosmosdb-community-v0",
  "steam_appid": 22380,
  "title": "Fallout: New Vegas",
  "status": "gold",
  "recommended_backend": "dxmt",
  "windows_version": "win10",
  "report_count": 2,
  "sources": ["curated-profile", "macgamingdb"],
  "notes": "Use the in-game launcher for resolution.",
  "updated_at": "2026-06-01T12:00:00Z"
}
```

Badge resolution priority: **curated profile** → **local report** → **community
entry** → cached MacGamingDB → cached ProtonDB.

## Normalized hint schemas

### AppleGamingWiki (`applegamingwiki-{appid}.json`)

```json
{
  "source": "applegamingwiki",
  "steam_appid": 22380,
  "page_title": "Fallout: New Vegas",
  "page_url": "https://applegamingwiki.com/wiki/Fallout:_New_Vegas",
  "compatibility": {
    "crossover": "playable",
    "wine": "playable",
    "parallels": "perfect"
  },
  "notes": {
    "crossover": "…",
    "wine": "…"
  }
}
```

AGW tier values include `perfect`, `playable`, `na`, `broken`, etc.

### MacGamingDB (`macgamingdb-{appid}.json`)

```json
{
  "source": "macgamingdb",
  "steam_appid": "1145360",
  "title": "Hades",
  "aggregated_performance": "EXCELLENT",
  "review_count": 12,
  "methods": { "native": 1, "crossover": 10, "parallels": 0, "other": 0 },
  "translation_layers": { "dxmt": 2, "d3d_metal": 8, "dxvk": 0, "none": 1 },
  "sample_notes": ["…"]
}
```

MacGamingDB performance tiers: `EXCELLENT`, `VERY_GOOD`, `GOOD`, `PLAYABLE`,
`BARELY_PLAYABLE`, `UNPLAYABLE`.

## Local report schema (`cosmosdb-report-v0`)

```json
{
  "schema": "cosmosdb-report-v0",
  "platform": "macos",
  "steam_appid": 22380,
  "status": "gold",
  "note": "Optional free text",
  "macos_version": "15.7.4",
  "chip": "Apple M2 Pro",
  "cosmos_backend": "dxmt",
  "wine_version": "11.8",
  "created_at": "2026-06-04T12:00:00Z"
}
```

### Status values

Same scale as profiles and [PROFILE_FORMAT.md](PROFILE_FORMAT.md):

`platinum` · `gold` · `silver` / `playable` · `bronze` · `broken` · `blocked`

### UMU (`umu-{appid}.json`)

```json
{
  "source": "umu",
  "steam_appid": 1091500,
  "umu_id": "umu-1091500",
  "title": "Cyberpunk 2077",
  "has_fix_database_entry": true,
  "store_entries": [
    { "title": "Cyberpunk 2077", "umu_id": "umu-1091500", "store": "egs", "codename": "Ginger" }
  ],
  "hint": "Port Proton fix ideas to Cosmos recipes; do not import GPL scripts."
}
```

Query: `GET …/umu_api.php?umu_id=umu-{steam_appid}`. Empty `store_entries` means no UMU listing.

## Dashboard

The Cosmos app shows a resolved compatibility badge in the Compatibility section
when a Steam App ID is selected. Buttons: **Sync Community DB**, **Suggest Profile
Draft** (when no curated YAML is selected), **Apply YAML Profile** (when one exists).

## Future work

- Expand community DB via GitHub PRs; optional signed release channel
- One-click merge of `suggest-profile` drafts after validation
- Merge external hints with profile `status` when generating launchers
