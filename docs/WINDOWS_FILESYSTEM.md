# Windows filesystem and environment structure

Cosmos manages a Wine prefix for each named Windows environment. Wine creates the
Windows registry and system folders during initialization. Cosmos keeps game
launch definitions, installer state and logs beside the prefix. This pass changes
path resolution and browsing; existing environments and games stay in place.

```text
~/Library/Application Support/Cosmos/
├── Bottles/<environment>/
│   ├── bottle.conf
│   ├── install-<game>.conf        installation destination and recovery state
│   ├── logs/launch.log
│   └── prefix/                   WINEPREFIX
│       ├── system.reg, user.reg, userdef.reg
│       ├── dosdevices/           Windows drive links, commonly c: and z:
│       └── drive_c/
│           ├── Games/<game>/     suggested installation destination
│           ├── Program Files/
│           ├── Program Files (x86)/
│           ├── users/<wine-user>/
│           │   ├── Documents/
│           │   ├── Saved Games/
│           │   └── AppData/
│           └── windows/
│               ├── system32/
│               └── syswow64/
├── Ports/<game>/port.conf        launcher definition
├── Runtime/                     downloaded runtime components
├── Profiles/, GameProfiles/     launcher and compatibility profiles
└── logs/                        main-environment logs
```

`COSMOS_SUPPORT_DIR`, `COSMOS_BOTTLES_DIR` and `COSMOS_PORTS_DIR` override their
respective locations. The legacy main Steam environment remains at
`~/.wine-steam-11`, or `WINEPREFIX` when explicitly configured. Selecting a named
environment uses that environment's own prefix. No migration is performed.

## Drives and paths

The shared `wine_filesystem` helpers serve the installer, port CLI, standalone
launches, saved-profile launches and import path resolver.

| Input | Resolution |
| --- | --- |
| `drive_c/Games/SimCity/SC3U.exe` | Physical `drive_c` inside the selected prefix |
| `C:\Games\SimCity\SC3U.exe` | The selected prefix's `dosdevices/c:` target; `drive_c` is the fallback |
| `D:\Game\Game.exe` | Existing `dosdevices/d:` target |
| Absolute Mac path | That host file/folder |

Windows drive paths accept forward/backward separators and resolve filename case
without guessing between ambiguous matches. Drive-relative paths such as
`C:Game.exe`, UNC paths and traversal above a drive/prefix root produce an error.
Prefix-relative paths stay within their selected root; existing Wine folder links
retain their destinations.

When converting a Mac installation folder to a Windows destination, Cosmos uses
the most specific existing drive mapping, preferring C: for an equal mapping.
An initialized environment with no drive covering an external folder reports an
error. A remapped Z: uses its actual target rather than assuming the Mac root.
For a new, uninitialized prefix only, the conventional C:/Z: defaults are assumed
and identified as assumptions in inspection output. Wine establishes the actual
prefix layout. Cosmos does not replace drive links automatically.

Windows user folders and drive mappings can reference Mac folders outside the
prefix. The exact location of saves depends on the game and its user-folder links.
Use the actual installed game's settings and files to locate a specific save.

## Browse and inspect

Select a port, then expand **Windows environment files**. Existing folders open
in Finder; missing or disconnected locations are labeled unavailable. The view
shows the environment, C: drive, game/user/program folders, system DLL folders
and actual drive links. Browsing creates no prefix, directory or drive mapping.

For a read-only JSON structure report:

```bash
./bottle.command filesystem game-simcity-3000-unlimited
python3 scripts/lib/wine_filesystem.py inspect "/path/to/prefix"
```

In a 64-bit/WoW64 prefix, `system32` contains 64-bit DLLs and `syswow64` contains
32-bit DLLs. A 32-bit-only prefix uses `system32` for 32-bit DLLs. SpockD3D9 must
match the game's architecture. The presence of these folders does not establish
runtime WoW64 support or game compatibility.

## Junctions and environment copies

The reader follows Wine's `user.WINEREPARSE` junction/symlink attributes, including
`?` stubs, without replacing them with Mac symlinks. It validates buffer bounds,
resolves target drives against this prefix, and rejects cycles/unmapped targets.
Ports retain Windows paths so a later junction update resolves at the next launch.
Check Game Files runs the same reader in the background and reports failures.

`bottle.command clone source --name backup` stops only positively identified Wine
processes belonging to the selected prefix/runtime, then copies the complete named
environment. Registry files, drive links, xattrs, settings and installer records
are retained. APFS clonefile is attempted before a regular copy. Absolute links
into the old prefix and installer destinations are rebased; external drive/Mac
folder links stay links. Those external folders are **not backed up**. Save the
game first. Existing destinations are refused and partial copies are not published.
Use a new port targeting the clone; existing ports and app shortcuts retain their
original environment. There is no in-place restore or automatic snapshot history.

## Reset and deletion

Bottles offers Clone Environment before a port exists. Clone before resetting if
Windows files, settings or saves inside the prefix need to be preserved.

Reset/delete require the existing confirmation or CLI `--force`. Both use scoped
Wine shutdown and refuse uncertain activity, linked bottle/prefix roots and
nested mounted folders. The selected tree is detached to a hidden `.cleanup-*`
sibling before Python's protected non-following removal. Ordinary drive/user
symlinks are removed as links; their external folders stay. Failure reports the
remaining tree's exact recovery path. That tree may already be partially removed;
this is not an undo feature. Unmount nested volumes and close Wine before retrying.

Reset keeps settings, logs and installer records. Delete removes the named
environment. Both keep port definitions/app shortcuts and external game folders;
reinstall games after reset, or edit/remove ports referencing a deleted environment.

## Environment workspace and settings

The redesigned screen separates browsing from launch targeting and shows assigned
games, folder/drive locations and registry architecture. Shared/legacy launchers
without a stored environment assignment are not counted as known owned games.
Named settings review changes, use an SHA-256 revision to reject stale edits, and
replace configuration atomically. An initialized prefix needs a new environment
for another architecture; saved preferences do not convert Windows files. Main
environment maintenance remains available separately.
