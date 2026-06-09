# Cosmos Community Compatibility Database

Git-hosted macOS compatibility entries for CosmosDB (roadmap **0.7**). Each game is
one JSON file under `games/<steam_appid>.json`.

## Schema

`cosmosdb-community-v0` — see [docs/COSMOSDB.md](../docs/COSMOSDB.md#community-database-cosmosdb-community-v0).

## Sync

Bundled copies ship in the Cosmos repo and app bundle. Users refresh into
Application Support with:

```bash
./cosmosdb.command sync
```

Optional remote mirror (raw GitHub or CDN base URL):

```bash
export COSMOS_COMMUNITY_DB_URL=https://raw.githubusercontent.com/awest813/Cosmos/main/cosmos-db
./cosmosdb.command sync
```

## Contributing

1. Add or edit `games/<appid>.json` following the schema.
2. Run `./scripts/test_cosmosdb_community.sh`.
3. Open a PR — entries are human-reviewed before merge.
