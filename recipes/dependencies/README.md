# Dependency Recipes

Winetricks-style building blocks installed into a bottle on demand. Profiles
reference these by ID in their `dependencies:` list.

## Format (`*.recipe`)

```
TYPE=dependency
ID=vcrun2015
DESCRIPTION=Microsoft Visual C++ 2015-2022 Redistributable
WINETRICKS=vcrun2015
```

## Apply

```bash
./repair.command list-deps
./repair.command install-dep vcrun2015
./profile.command apply profiles/steam/steam-22380-fallout-new-vegas.yaml
```

Winetricks is **LGPL** — invoked as an external tool; see [docs/LICENSING.md](../docs/LICENSING.md).

## Shipped recipes

| ID | Winetricks verb |
| --- | --- |
| `vcrun2010` | `vcrun2010` |
| `vcrun2015` | `vcrun2015` |
| `vcrun2019` | `vcrun2019` |
| `dotnet48` | `dotnet48` |
| `corefonts` | `corefonts` |
| `d3dx9` | `d3dx9` |

### winemactricks-json import

Mac-oriented tweaks from [winemactricks-json](https://github.com/Alien4042x/winemactricks-json)
(MIT) are imported into `recipes/fixes/`:

```bash
./scripts/import_winemactricks.sh          # from vendored JSON
./scripts/import_winemactricks.sh --sync   # refresh JSON, then import
```

Generated recipes include `SOURCE=winemactricks:<id>` and are safe to re-run
(idempotent; skips hand-written recipes unless `--force`).

Add more by copying a `.recipe` file, importing from winemactricks-json, or
listing a verb from [winetricks](https://github.com/Winetricks/winetricks).
</content>
