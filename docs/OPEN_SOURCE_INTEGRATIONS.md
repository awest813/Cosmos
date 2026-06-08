# Open Source Integrations

How Cosmos uses external MIT-friendly (or external-tool) projects across the
integration priorities.

## 1. Harden detection

**In Cosmos today**

- `detect_steam_games.command` scans `libraryfolders.vdf` and `appmanifest_*.acf`
  inside the Wine prefix (not native macOS Steam).
- Tool/runtime App IDs are filtered via `IGNORED_APPIDS` and name heuristics.

**Added**

- `--verify` runs `scripts/verify_steam_detection.command` (installdir on disk).
- Optional `COSMOS_VERIFY_NODE=1` with [@ciberus/find-steam-app](https://github.com/Ciberusps/find-steam-app) (MIT).

```bash
./detect_steam_games.command --verify
./scripts/verify_steam_detection.command
COSMOS_VERIFY_NODE=1 ./scripts/verify_steam_detection.command
```

**Reference implementations**

| Project | License | Use |
| --- | --- | --- |
| [find-steam-app](https://github.com/Ciberusps/find-steam-app) | MIT | Cross-check library/manifest parsing |
| [steamutils](https://github.com/bomkz/steamutils) | Unlicense | Go parser reference |
| [Gameloop.Vdf](https://github.com/shravan2x/Gameloop.Vdf) | MIT | VDF grammar reference |

## Dashboard UI

The SwiftUI app surfaces these tools in the main detail view:

- **Verify Detection** — Setup grid button → `detect_steam_games.command --verify`
- **Curated Game Profiles** — YAML cards → `profile.command show` / `apply`
- **Repair & Dependencies** — Diagnose Logs + recipe buttons → `repair.command`
- **Compatibility** — ProtonDB lookup + local macOS report → `cosmosdb.command`

When a bottle is selected, `COSMOS_BOTTLE` is passed to CLI commands automatically.

## 2. Repair engine (0.5)

**In Cosmos today**

- `repair.command` — `list-deps`, `list-fixes`, `install-dep`, `apply-fix`
- Recipes: `recipes/*/*.recipe` (KEY=value)
- Winetricks invoked as external **LGPL** tool ([docs/LICENSING.md](LICENSING.md))

```bash
./repair.command list-deps
./repair.command install-dep vcrun2015
./repair.command apply-fix clear_steam_caches
```

Fix categories align with [Cellar](https://github.com/lasermaze/Cellar) / [D4Mac](https://github.com/MichaelLod/D4Mac) docs (caches, kill Wine, Windows version).

## 3. CosmosDB (0.7)

- `cosmosdb.command` — ProtonDB lookup + local macOS JSON reports
- See [COSMOSDB.md](COSMOSDB.md)

## 4. Profiles (0.4)

- `profile.command` — `list`, `show`, `export-override`, `apply`
- Lutris field mapping: [LUTRIS_MAPPING.md](LUTRIS_MAPPING.md)

```bash
./profile.command apply profiles/steam/steam-22380-fallout-new-vegas.yaml
```

## 5. License hygiene

See [LICENSING.md](LICENSING.md) — DXMT pin, GPTK user-supply, winetricks external use.
