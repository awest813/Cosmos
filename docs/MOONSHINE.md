# OpenGL fix and launch logs

[Moonshine](https://github.com/ybmeng/moonshine) is a GPL-3.0 fork of Whisky. Cosmos does not include Moonshine or Whisky source. The behaviors below are Cosmos's own implementation of the same ideas: an OpenGL 3.2 check, a crash note, a more detailed Wine log, and launching a program from its own folder.

## OpenGL 3.2

Some programs, including SDL3, ask Wine's Mac driver for an OpenGL 3.2 context. Moonshine's Wine Staging 11.2 build has a conditional jump at byte `0x329fb` in `winemac.so` (`0x74`). Flipping that one byte to `0xEB` makes the check succeed.

Cosmos looks for `winemac.so` next to the installed Wine (`Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so`). It writes `0xEB` only when the byte at that offset is still `0x74`. If the byte is already `0xEB`, nothing changes. Any other byte, or a shorter file, is left alone. That matters because Cosmos pins Wine 11.8, and a newer build may not use the same offset.

The original byte is saved beside the driver as `winemac.so.cosmos-bak`. Undo restores that byte, or writes `0x74` when the driver is flipped and no backup exists.

Wine install never fails because this check does not match.

| Control | Meaning |
| --- | --- |
| `COSMOS_OPENGL_PATCH=auto` | Default. Apply only when the byte is `0x74`. Stay quiet otherwise. |
| `COSMOS_OPENGL_PATCH=on` | Same apply rule, and print a warning when the build does not match. |
| `COSMOS_OPENGL_PATCH=off` | Do not change the driver. |
| `COSMOS_OPENGL_PATCH_OFFSET` | Decimal or `0x` hex override for tests and a future Wine build. |
| `COSMOS_WINEMAC_SO` | Use this driver file instead of the installed Wine copy. |

```bash
./run.command --opengl-status
./run.command --opengl-patch
./run.command --opengl-revert
```

The dashboard card is **OpenGL (Moonshine)** under Performance & Graphics. The same check also runs at the end of a Wine install when the mode is `auto` or `on`.

## Logs

`COSMOS_WINEDEBUG_PRESET` chooses the log line used when `WINEDEBUG` is not already set:

| Preset | `WINEDEBUG` |
| --- | --- |
| `cosmos` (default) | `-all,err+all` |
| `moonshine` | `fixme-all,err+all,warn+module` |

An explicit `WINEDEBUG` value always wins. The dashboard picker labels these **Quiet** and **Detailed**.

When a foreground launch, or a detached launch that is being retried, still fails, Cosmos appends a note with the status and a reason: `exit`, or `uncaught signal` when the status is 128–159. Up to eight existing log lines that mention a page fault, `err:`, an unhandled exception, or a DLL load failure are copied under that note. The program's exit code is unchanged.

## Working directory

Profile games, standalone games, and installers start with the executable's folder as the working directory. Cosmos already runs `wine <program>` directly. The folder change is the remaining piece so a program can find DLLs and data beside its `.exe`.

## License boundary

Moonshine and Whisky are GPL-3.0. Combining their Swift source with Cosmos would pull Cosmos under GPL-3.0. Cosmos keeps its LGPL-3.0-or-later license. Do not copy Moonshine or Whisky sources into this repository. The offset above is a fact about a Wine binary, not a copy of Moonshine's installer.
