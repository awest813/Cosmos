# Fix Recipes

One-click fixes applied by the repair engine (0.5). Profiles reference these by
ID in their `fixes:` list, and the repair UI can suggest them when it detects a
known failure pattern.

Planned fix IDs:

- `disable_intro_video` — skip intro/splash videos that hang under Wine
- `force_borderless` — force borderless/windowed mode
- `force_windowed` — force windowed mode
- `kill_wine` — kill stuck Wine processes
- `rebuild_prefix` — recreate the bottle's Wine prefix
- `clear_steam_caches` — clear Steam shader/config caches
- `fix_controller_mapping` — apply controller mapping fixes
- `set_windows_version` — set the reported Windows version
- `dll_override` — apply specific Wine DLL overrides

Each fix will be a declarative recipe describing the registry edits, file
operations, env changes, or process actions it performs. The format lands with
the 0.5 repair engine.
</content>
