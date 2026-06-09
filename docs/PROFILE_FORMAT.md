# Cosmos Profile Format (v0)

A **profile** is the known-good recipe for launching one game. Profiles are what
make Cosmos Proton-ish: the value is as much in curated per-game defaults as in
the runtime itself.

Profiles are stored as YAML (JSON is also accepted) under `profiles/`, organized
by store:

```
profiles/
├── steam/
│   └── steam-22380-fallout-new-vegas.yaml
├── itch/
│   └── itch-<slug>.yaml
├── battlenet/
│   └── battlenet-<slug>.yaml
└── standalone/
    └── <slug>.yaml
```

File naming convention: `<store>-<id>-<slug>.yaml` (e.g.
`steam-22380-fallout-new-vegas.yaml`). For standalone games without a store ID,
use `standalone-<slug>.yaml`.

## v0 schema

```yaml
id: fallout_new_vegas          # required, unique slug
name: "Fallout: New Vegas"     # required, display name
store: steam                   # steam | gog | epic | itch | battlenet | standalone
steam_appid: 22380             # required when store == steam
exe_path: ""                   # required when store == itch | battlenet | standalone (relative to bottle drive_c)
status: playable               # see status values below
recommended_backend: dxmt      # recommended | d3dmetal | dxmt | dxvk | wined3d
wine_version: cosmos-stable    # runtime identifier or pinned Wine version
settings:
  retina: false                # Wine Mac Driver RetinaMode
  windows_version: win10       # winxp | win7 | win8 | win10 | win11
  esync: true
  env:                         # extra environment variables passed to the runtime
    DXMT_CONFIG: "d3d11.preferredMaxFrameRate=60;"
dependencies:                  # winetricks-style; resolved against recipes/dependencies/
  - vcrun2010
  - d3dx9
fixes:                         # resolved against recipes/fixes/
  - disable_intro_video
  - force_borderless
notes: "Use launcher first, then set resolution."
```

### Field reference

| Field | Required | Notes |
| --- | --- | --- |
| `id` | yes | Stable unique slug; used for cross-references. |
| `name` | yes | Human-readable title. |
| `store` | yes | One of `steam`, `gog`, `epic`, `itch`, `battlenet`, `standalone`. |
| `steam_appid` | when `store: steam` | Steam application ID. |
| `exe_path` | when `store: itch`, `battlenet`, or `standalone` | Path to the game EXE, relative to the bottle's `drive_c`. |
| `status` | yes | Compatibility rating (see below). |
| `recommended_backend` | yes | Graphics backend; see [BACKENDS.md](BACKENDS.md). |
| `wine_version` | yes | Runtime identifier (e.g. `cosmos-stable`) or pinned version. |
| `settings.retina` | no | Toggle Wine Retina mode (default `false`). |
| `settings.windows_version` | no | Reported Windows version. |
| `settings.esync` | no | Enable esync. |
| `settings.env` | no | Map of extra environment variables. |
| `dependencies` | no | List of dependency recipe IDs from `recipes/dependencies/`. |
| `fixes` | no | List of fix recipe IDs from `recipes/fixes/`. |
| `notes` | no | Free-text guidance shown in the UI. |

### Status values

Matches the CosmosDB rating scale:

- `platinum` — works out of the box
- `gold` — works with small fixes
- `silver` / `playable` — playable with issues
- `bronze` — launches but rough
- `broken` — does not work
- `blocked` — anti-cheat / DRM / AVX / etc.

## Validation

Run `./profile.command validate` to lint every profile (or
`./profile.command validate <path-or-id>` for one). It checks that the required
fields are present, that `store`, `status`, `recommended_backend`, and
`settings.windows_version` use allowed values, that `store: steam` profiles have
a numeric `steam_appid` whose value matches the `steam-<appid>-<slug>.yaml`
filename, and that every `dependencies`/`fixes` entry resolves to a recipe under
`recipes/`. CI runs the same check via `scripts/test_profiles.sh`, so a typo in a
backend name, status, or recipe id fails the build instead of silently shipping.

## Relationship to today's `cosmos_configs/*.conf`

The current per-game configs are flat shell files that declare env-var presets:

```sh
APP_NAME="Binding of Isaac (Cosmos)"
BUNDLE_ID="com.cosmos.binding-of-isaac"
RUN_ENV_NAMES=( STEAM_GAME_ID DXMT_CONFIG )
STEAM_GAME_ID="250900"
DXMT_CONFIG="d3d11.preferredMaxFrameRate=60;"
```

The equivalent v0 profile is:

```yaml
id: binding_of_isaac
name: "The Binding of Isaac: Rebirth"
store: steam
steam_appid: 250900
status: playable
recommended_backend: dxmt
wine_version: cosmos-stable
settings:
  env:
    DXMT_CONFIG: "d3d11.preferredMaxFrameRate=60;"
```

App-bundle metadata (`APP_NAME`, `BUNDLE_ID`, icon) moves out of the profile and
into the Launcher layer's `.app` generator, derived from `name`/`id` by default.

Migration is a 0.4 task; both formats may coexist during the transition.
</content>
