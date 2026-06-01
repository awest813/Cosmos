# Cosmos Profiles

Per-game launch recipes — the "known-good defaults" that make Cosmos Proton-ish.

See [`docs/PROFILE_FORMAT.md`](../docs/PROFILE_FORMAT.md) for the full v0 schema.

## Layout

```
profiles/
├── steam/        # store == steam, named steam-<appid>-<slug>.yaml
└── standalone/   # store == standalone, named standalone-<slug>.yaml
```

## Adding a profile

1. Copy an existing profile in the matching store folder.
2. Set `id`, `name`, `store`, the store ID (`steam_appid`) or `exe_path`,
   `status`, and `recommended_backend`.
3. Reference dependency/fix recipe IDs from `recipes/dependencies/` and
   `recipes/fixes/`.
4. Add `notes` for any manual steps a player needs to know.

The current `merlot_configs/*.conf` files are the predecessor of these profiles;
migrating them is a 0.4 roadmap task.
</content>
