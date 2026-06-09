# macos-wine-steam / Merlot configs (vendored)

Upstream: https://github.com/ByMedion/macos-wine-steam (MIT)

Per-game launcher presets live in `merlot_configs/*.conf`. Cosmos imports them into
YAML profiles via:

```bash
./scripts/import_macos_wine_steam.sh
```

Refresh from upstream with `--sync` before importing.
