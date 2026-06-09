# CosmosDB (v0 preview)

CosmosDB is Cosmos's compatibility layer: **hints from community sources** plus
**local macOS reports** from real runs. Roadmap milestone **0.7**.

## Data sources

| Source | Role | License / terms |
| --- | --- | --- |
| [ProtonDB Community API](https://github.com/Trsnaqe/protondb-community-api) | Linux/Proton ratings by Steam App ID | MIT |
| [AppleGamingWiki](https://applegamingwiki.com/) | macOS Wine / CrossOver / Parallels tiers + notes | Community wiki (CC BY-SA); MediaWiki API |
| [MacGamingDB](https://macgamingdb.app/) | Apple Silicon FPS benchmarks, play method, translation layer | Community site; public read REST API |
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
- `COSMOSDB_CACHE_TTL_SECONDS` — cache lifetime (default `86400`)
- `COSMOSDB_HTTP_USER_AGENT` — User-Agent for wiki/API requests

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

## Future work

- GitHub-hosted shared macOS report database (roadmap 0.7)
- Dashboard badges wired to `lookup` + local reports
- Merge external hints with profile `status` when generating launchers
