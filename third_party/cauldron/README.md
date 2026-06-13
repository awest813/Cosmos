# Cauldron (reference upstream)

Upstream: https://github.com/cashcon57/cauldron  
License: **LGPL-2.1** (see upstream `LICENSE`)

Cauldron is a paused-but-substantial macOS game compatibility layer: custom Wine
fork, Rust core, SwiftUI frontend, and per-game launch intelligence (sync toggles,
CPU topology, exe overrides, registry entries, graphics backend staging).

Cosmos does **not** vendor or bundle Cauldron. We treat it as a **reference and
profile-seeding source** under LGPL-2.1:

- Game compatibility hints from `db/seed.sql` are reimplemented as Cosmos YAML
  profiles (`profiles/steam/`) and documented in [docs/CAULDRON.md](../../docs/CAULDRON.md).
- Architecture ideas (launch resolver layers, `steamwebhelper` DLL protection,
  per-app macdrv registry) inform Cosmos roadmap items; see
  [ADOPTION_PLAN.md](../../docs/ADOPTION_PLAN.md).

To refresh portable hints from upstream:

```bash
./scripts/import_cauldron_hints.sh --list
./scripts/import_cauldron_hints.sh --diff   # games in Cauldron seed missing Cosmos profiles
```

**Not ported (by design):**

- Cauldron's Wine fork and Rust/SwiftUI app (different stack; Cosmos is bash + SwiftUI dashboard).
- Bundled D3DMetal runtime from CrossOver (licensing).
- GPL-adjacent Proton script bulk imports (Cosmos reimplements as YAML/recipes).
