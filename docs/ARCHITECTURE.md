# Cosmos Architecture

Cosmos is organized as **layers**, not a flat bag of features. Each layer has a
clear responsibility and can be built, tested, and reasoned about on its own.
This is what lets Cosmos grow from "Wine + Steam scripts" into a real
Proton-style compatibility layer without a giant rewrite.

```
Cosmos App
│
├── UI Layer
│   ├── Game library
│   ├── Bottle manager
│   ├── Settings
│   ├── Logs
│   └── Repair tools
│
├── Profile Layer
│   ├── Per-game YAML/JSON configs
│   ├── Compatibility ratings
│   ├── Recommended backends
│   └── Fix recipes
│
├── Runtime Layer
│   ├── Wine builds
│   ├── Rosetta checks
│   ├── Winetricks-style installers
│   └── Steam/GOG/Epic support
│
├── Graphics Layer
│   ├── D3DMetal / GPTK
│   ├── DXMT
│   ├── DXVK / MoltenVK
│   └── WineD3D fallback
│
└── Launcher Layer
    ├── .app generator
    ├── Steam game launch
    ├── Standalone EXE launch
    └── Controller/console mode
```

## Layer responsibilities

### UI Layer
The user-facing app. Game library, bottle manager, per-game settings, log viewer,
and repair tools. Two modes long-term: **Desktop mode** (manage bottles/settings)
and **Console mode** (fullscreen, controller-driven, sit-back-and-play).

### Profile Layer
The "known-good defaults" brain — what makes Cosmos Proton-ish rather than a raw
Wine wrapper. Per-game configs declare the recommended backend, Wine/Windows
version, dependencies, fixes, and notes. Backed locally by files and eventually
by the community **CosmosDB**. Schema: [PROFILE_FORMAT.md](PROFILE_FORMAT.md).

### Runtime Layer
Everything below the graphics translation: Wine builds, Apple Silicon/Rosetta
checks, a winetricks-style dependency installer, prefix/bottle lifecycle, and
store integration (Steam first, then GOG/Epic/itch/standalone EXE). At 1.0 this
layer ships a bundled, versioned **Cosmos Runtime**.

### Graphics Layer
Swappable D3D→Metal translation backends, selected per game. See
[BACKENDS.md](BACKENDS.md). Cosmos treats backends as tools, not as a fixed choice.

### Launcher Layer
Turns a configured game into something launchable: generates `.app` bundles into
`/Applications/Cosmos Apps/`, launches by Steam App ID or EXE path, and (later)
drives controller/console mode.

## How today's code maps onto the layers

The current scripts already implement vertical slices of several layers.
Nothing here is greenfield — Cosmos is a refactor-and-grow, not a rewrite.

| Cosmos layer | Implemented today by | Status |
| --- | --- | --- |
| UI | `app/CosmosApp.swift` + `app/ContentView.swift` (SwiftUI dashboard, built via `Package.swift` / `scripts/build_cosmos_app.command`) + generated `.app`s | **Partial** — early dashboard shell; library/bottle/repair views still to come |
| Profile | `cosmos_configs/*.conf` (env-var presets per game) | **Partial** — flat shell configs, no schema/ratings/recipes yet |
| Runtime | `run.command` (Wine download, prefix init, Steam install, Rosetta + macOS checks) | **Partial** — single hardcoded Steam bottle |
| Graphics | `run.command` DXMT default + opt-in `GPTK_PATH` (D3DMetal) | **Partial** — two backends, env-driven, no per-game switch UI |
| Launcher | `detect_steam_games.command` (auto-detect) + `install_cosmos.command` + `app/cosmos/CosmosLauncher` (`.app` generator) | **Partial** — auto-detects Steam games (multi-library, StateFlags filtering), generates `.app`s with Steam artwork icons |

Key existing primitives worth preserving as Cosmos grows:

- **`run.command`** — the runtime engine. Flags `--steam`, `--profiles`,
  `--game <path> [args...]` already hint at the Launcher↔Runtime boundary.
- **`CosmosLauncher` + `cosmos.env`** — proof that one shared launcher binary can
  drive many generated apps via per-app env. The Cosmos `.app` generator
  generalizes this.
- **`cosmos_configs/*.conf`** — the proto-profile. The v0 profile schema replaces
  these flat `RUN_ENV_NAMES` shell files with structured YAML/JSON.
- **Backend selection via `GPTK_PATH` / DXMT install** — becomes a first-class
  per-bottle / per-game `backend` enum.

## Data & filesystem layout (target)

```
~/Library/Application Support/Cosmos/
├── bottles/            # one dir per bottle (Wine prefix + metadata)
│   └── <bottle>/
│       ├── prefix/         # WINEPREFIX
│       ├── bottle.yaml      # wine version, windows version, backend, env, deps
│       └── logs/
├── runtimes/           # downloaded Wine builds, DXMT, etc.
├── profiles/           # cached/installed game profiles
└── logs/               # app-level logs
```

> Note: today's scripts use `~/.wine-steam-11` (prefix) and store saved profiles
> under `~/Library/Application Support/Cosmos/Profiles/` (with a fallback to the
> legacy `Cider/Profiles/` location). The per-bottle layout above is the 0.3 target.

## Proposed repo structure

The repository grows toward the layout below as features land. Directories are
added when there's real content to put in them, not pre-emptively.

```
Cosmos/
├── app/                # frontend + backend (today: app/cosmos/ launcher)
│   ├── frontend/
│   └── backend/
├── runtimes/           # runtime integration helpers (wine, dxmt, moltenvk)
├── profiles/           # per-game profiles
│   ├── steam/
│   └── standalone/
├── recipes/            # reusable building blocks for the repair/profile engine
│   ├── dependencies/   # winetricks-style dependency recipes
│   └── fixes/          # one-click fix recipes
├── scripts/            # bootstrap-steam.sh, create-bottle.sh, launch-game.sh, generate-app.sh
│                       #   (today: run.command, install_cosmos.command, uninstall.command)
├── docs/               # ROADMAP.md, ARCHITECTURE.md, PROFILE_FORMAT.md, BACKENDS.md
└── cosmos-db/          # community compatibility database (0.7+)
```

## Tech stack direction

No final commitment yet; the layered design keeps this swappable. Candidate
frontends, in order of fit for an AI-assisted, web-skilled developer:

1. **Tauri + TypeScript** (Rust command backend, shell helpers) — light, good
   process/file control, web UI skills transfer. *Leading candidate.*
2. **SwiftUI + shell backend** — most native Mac polish and best `.app`
   integration; Swift learning curve. *Pick this if native feel wins.*
3. **Electron + React + Node** — easiest path, most examples; heavier, less
   native polish.

Regardless of frontend, the Runtime/Graphics layers stay shell/process-driven
(as they are today), so the choice is mostly a UI-layer decision.
</content>
