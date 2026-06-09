# winemactricks-json (vendored)

Upstream: https://github.com/Alien4042x/winemactricks-json (MIT)

Community-maintained tweak database for macOS Wine wrappers. Cosmos imports
entries into `recipes/fixes/` via:

```bash
./scripts/import_winemactricks.sh
```

Do not edit `winemactricks.json` by hand — refresh from upstream with
`./scripts/import_winemactricks.sh --sync` then re-run the import.
