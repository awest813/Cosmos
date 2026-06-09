# Open Source Integrations

How Cosmos uses external MIT-friendly (or external-tool) projects across the
integration priorities.

> **Phased adoption plan:** see [ADOPTION_PLAN.md](ADOPTION_PLAN.md) for
> winemactricks-json, wineregdiff, VDF libraries, UMU API, profile seeding,
> and Runtime 1.0 bundling priorities.

## Steam install & launch (MIT: steam-on-m1-wine)

Upstream: https://github.com/notpop/steam-on-m1-wine (MIT)

**Vendored in Cosmos**

| Path | Upstream | Purpose |
|------|----------|---------|
| `third_party/steam-on-m1-wine/wrapper/` | `wrapper/` | C `steamwebhelper.exe` that injects `--disable-gpu --single-process` |
| `third_party/steam-on-m1-wine/assets/` | `scripts/assets/` | Japanese font substitution + optional virtual-desktop registry |

**Integrated at runtime**

| Component | What it does |
|-----------|--------------|
| `scripts/lib/steam_lib.sh` | Prefix prep, launch hardening, VDF parsing, wrapper install |
| `scripts/install_steamwebhelper_wrapper.command` | Standalone wrapper build/install (needs `brew install mingw-w64`) |
| `run.command --setup-steam` | Seeds fonts, CA bundle, DXMT prefix DLLs, wrapper (when possible) |
| `run.command --steam` | Stops lingering Wine, clears Chromium locks, applies DLL overrides + launch flags |

**Defaults in `steam.conf`**

```bash
STEAM_LAUNCH_ARGS="-no-cef-sandbox -cef-single-process -noverifyfiles"
COSMOS_STEAM_WEBHELPER_WRAPPER="1"    # build/install wrapper when mingw-w64 exists
COSMOS_STEAM_SEED_FONTS="1"           # copy macOS CJK fonts into prefix
COSMOS_STEAM_CA_BUNDLE="1"            # copy /etc/ssl/cert.pem into prefix
COSMOS_STEAM_WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"
WINE_VIRTUAL_DESKTOP="auto"           # wrap Steam in a Wine virtual desktop (set "" to opt out)
```

**Repair fixes**

```bash
./repair.command apply-fix install_steamwebhelper_wrapper
./repair.command apply-fix seed_japanese_fonts
./repair.command apply-fix fix_steam_ssl
./repair.command apply-fix reinstall_steam
```

**Not ported (upstream-specific)**

- Homebrew `wine-stable` install — Cosmos uses Gcenx tarballs instead
- LLVM 15 self-build + Wine `-fvisibility=default` rebuild — experimental; see upstream `docs/building-for-games.md`
- DXMT fork nightly pipeline — Cosmos pins official DXMT releases

## 1. Harden detection

**In Cosmos today**

- `detect_steam_games.command` scans `libraryfolders.vdf` and `appmanifest_*.acf`
  inside the Wine prefix (not native macOS Steam).
- Tool/runtime App IDs are filtered via `IGNORED_APPIDS` and name heuristics.

**Added**

- `--verify` runs `scripts/verify_steam_detection.command` (installdir on disk).
- Partial installs are skipped by default via `StateFlags` checks and
  `appmanifest_*.acf.tmp.save` stale-manifest detection (patterns from
  [find-steam-app](https://github.com/Ciberusps/find-steam-app) edge cases).
  Set `COSMOS_DETECT_INCLUDE_PARTIAL=1` to include in-progress downloads.
- Shared helpers in `scripts/lib/steam_lib.sh` locate manifests across secondary
  Steam libraries and verify each game's `installdir` in the correct folder.
- Optional `COSMOS_VERIFY_NODE=1` with [@ciberus/find-steam-app](https://github.com/Ciberusps/find-steam-app) (MIT).
- Unit tests: `./scripts/test_steam_detection.sh` (runs in CI; uses fixtures under
  `scripts/fixtures/steam_detection/`).

```bash
./detect_steam_games.command --verify
./scripts/verify_steam_detection.command
COSMOS_VERIFY_NODE=1 ./scripts/verify_steam_detection.command
```

**Reference implementations**

| Project | License | Use |
| --- | --- | --- |
| [find-steam-app](https://github.com/Ciberusps/find-steam-app) | MIT | Cross-check library/manifest parsing; v1/v2 `libraryfolders.vdf` |
| [steamutils](https://github.com/bomkz/steamutils) | Unlicense | Go parser reference |
| [Gameloop.Vdf](https://github.com/shravan2x/Gameloop.Vdf) | MIT | VDF grammar reference |
| [macos-wine-steam](https://github.com/ByMedion/macos-wine-steam) | MIT | Direct lineage; Gcenx Wine + DXMT bootstrap |

## Dashboard UI

The SwiftUI app surfaces these tools in the main detail view:

- **Verify Detection** — Setup grid button → `detect_steam_games.command --verify`
- **Curated Game Profiles** — YAML cards → `profile.command show` / `apply`
- **Repair & Dependencies** — Diagnose Logs + recipe buttons → `repair.command`
- **Compatibility** — ProtonDB + AppleGamingWiki + MacGamingDB hints + local report → `cosmosdb.command`

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
./repair.command apply-fix install_steamwebhelper_wrapper
```

Fix categories align with [Cellar](https://github.com/lasermaze/Cellar) / [D4Mac](https://github.com/MichaelLod/D4Mac) docs (caches, kill Wine, Windows version).

## 3. CosmosDB (0.7)

- `cosmosdb.command` — ProtonDB + AppleGamingWiki + MacGamingDB lookups + local macOS JSON reports
- See [COSMOSDB.md](COSMOSDB.md)

### AppleGamingWiki + MacGamingDB (0.7)

| Source | Integration | Lookup |
| --- | --- | --- |
| [AppleGamingWiki](https://applegamingwiki.com/) | MediaWiki search + `Compatibility/macOS` parse | `./cosmosdb.command lookup <appid> applegamingwiki` |
| [MacGamingDB](https://macgamingdb.app/) | Public REST `GET /games/{steamAppId}` | `./cosmosdb.command lookup <appid> macgamingdb` |

Parsers and HTTP helpers live in `scripts/lib/cosmosdb_lib.sh`. Unit tests:
`./scripts/test_cosmosdb_lib.sh` (fixture-based, no network).

## 4. Profiles (0.4)

- `profile.command` — `list`, `show`, `export-override`, `apply`
- Lutris field mapping: [LUTRIS_MAPPING.md](LUTRIS_MAPPING.md)

```bash
./profile.command apply profiles/steam/steam-22380-fallout-new-vegas.yaml
```

## 5. License hygiene

See [LICENSING.md](LICENSING.md) — DXMT pin, GPTK user-supply, winetricks external use.
