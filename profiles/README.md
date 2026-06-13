# Cosmos Profiles

Per-game launch recipes — the "known-good defaults" that make Cosmos Proton-ish.

See [`docs/PROFILE_FORMAT.md`](../docs/PROFILE_FORMAT.md) for the full v0 schema.

## Layout

```
profiles/
├── steam/        # store == steam, named steam-<appid>-<slug>.yaml
├── gog/          # store == gog, named gog-<slug>.yaml
├── itch/         # store == itch, named itch-<slug>.yaml
├── battlenet/    # store == battlenet, named battlenet-<slug>.yaml
├── standalone/   # store == standalone, named standalone-<slug>.yaml
└── drafts/       # WIP drafts (excluded from shipped validation counts)
```

Personal profiles created in the Cosmos app are saved under
`~/Library/Application Support/Cosmos/GameProfiles/<store>/` and loaded alongside
bundled profiles.

## Adding a profile

1. Copy an existing profile in the matching store folder, or use **Add Profile** in
   the dashboard Games tab (Steam App ID or GOG slug).
2. Set `id`, `name`, `store`, the store ID (`steam_appid`, `gog_slug`, or
   `exe_path`), `status`, and `recommended_backend`.
3. Reference dependency/fix recipe IDs from `recipes/dependencies/` and
   `recipes/fixes/`.
4. Add `notes` for any manual steps a player needs to know.
5. Run `./profile.command validate <path>` before committing shipped profiles.

During game detection, `detect_steam_games.command` auto-exports
`cosmos_configs/overrides/<appid>.env` from a matching profile when the user has
not authored an override yet. Apply dependencies and fixes with
`./profile.command apply profiles/steam/<file>.yaml`.

Generate a draft from community hints:

```bash
./cosmosdb.command suggest-profile <APPID> --write   # → profiles/drafts/
./profile.command validate profiles/drafts/steam-<APPID>-<slug>.yaml
```

</content>
