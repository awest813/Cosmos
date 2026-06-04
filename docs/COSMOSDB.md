# CosmosDB (v0 preview)

CosmosDB is Cosmos's compatibility layer: **hints from community sources** plus
**local macOS reports** from real runs. Roadmap milestone **0.7**.

## Data sources

| Source | Role | License |
| --- | --- | --- |
| [ProtonDB Community API](https://github.com/Trsnaqe/protondb-community-api) | Linux/Proton ratings by Steam App ID | MIT |
| Local `~/Library/Application Support/Cosmos/CosmosDB/reports/` | macOS-specific user reports | User data |

ProtonDB is a **hint only** on macOS — backends differ (DXMT/D3DMetal vs Proton).

## CLI (`cosmosdb.command`)

```bash
./cosmosdb.command lookup 22380          # ProtonDB summary (24h cache)
./cosmosdb.command report 22380 gold "Stable on M2, DXMT, win10 bottle"
./cosmosdb.command list-reports
./cosmosdb.command cache-clear
```

Environment:

- `COSMOS_PROTONDB_API_URL` — API base (default: protondb-community-api.vercel.app)
- `COSMOSDB_DIR` — override storage root

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
- Merge ProtonDB hints with profile `status` when generating launchers
