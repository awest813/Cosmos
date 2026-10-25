# Sikarugir-first release readiness

Current priority: the existing Sikarugir-style **Ports** experience, setup UI/UX,
32-bit programs through WoW64, and SpockD3D9. The work follows the current main
branch's Ports and split-dashboard architecture.

## Changes in this pass

- Dashboard/CLI port launches now pass the program's saved bitness, as generated
  apps already do. Both routes preserve quoted, empty, and literal wildcard
  arguments and stop before launching on malformed quotes.
- WineD3D fallback explicitly uses builtin D3D9 while preserving other DLL
  overrides. Matching Spock DLLs restore the native path. Existing win32 registry
  markers control DLL placement; conflicting win32/win64 preferences fail safely.
- Spock validation accepts both `Intel i386` and `Intel 80386` descriptions from
  `file`. The setup card explains x86 requirements, names the target environment,
  and labels the dual-architecture build action. Warnings wrap fully.
- Ports directory overrides match between the native dashboard and CLI. Pending
  Terminal work disables port mutations and launch actions.
- Read-only game preflight records prefix architecture, rejects x64 games in
  win32 prefixes, and explains that x86/WoW64 runtime support needs actual testing.
- Ports, Bottles, and import navigation are available before Steam setup. Ports
  links to graphics downloads; existing Spock folder selection can open Graphics
  settings before Steam is installed. Rosetta installation uses Terminal before
  port launch, with an explicit action label.
- Executable selection and CLI creation detect x86/x64 headers, with explicit
  architecture mismatches rejected. Apple Silicon/macOS 14.6 requirements are
  checked by the dashboard, CLI, and generated apps, including Rosetta Terminal.
- Failed creation retains the form and displays the error for retry. Port
  selection stays available during jobs; creation/build/launch remain guarded.
- Fresh ports with WineD3D enabled can launch before Spock is built, with builtin
  D3D9 selected and no unnecessary MoltenVK request. Explicit invalid Spock paths
  still produce an error.
- Ports offers installation and interrupted-installation recovery directly.
  Custom installation folders persist per game/environment; disconnected folders
  fail with guidance, and moved folders can be supplied explicitly. Recovery
  never reruns the installer. Spock-only renderer descriptions no longer claim
  DXMT or WineD3D fallback is enabled when its switch is off.

## Evidence and release gates

Filesystem handling now uses a shared resolver for the installer, standalone and
profile launches, port commands and imports. It supports absolute Windows drive
paths, unambiguous case-insensitive lookup and actual Wine drive mappings, rejects
root escapes/drive-relative paths, and reports unmapped external destinations.
Read-only layout inspection is available in Ports and `bottle.command filesystem`.
Python fixtures cover mapped/remapped/broken drives and selected-prefix isolation;
native fixtures verify folder discovery without creating/modifying data. Existing
environments stay in place. The bundled [filesystem guide](WINDOWS_FILESYSTEM.md)
describes the current layout and default assumptions for uninitialized prefixes.

Installation state now records preparation, setup started/failed, waiting for an
EXE, and registration. The native Ports page lists unfinished records and prefills
Finish/Retry with the saved title, installer and environment. Registered ports
and invalid metadata are excluded. Continuing preserves the saved-folder guard
for disconnected drives. Game selection offers up to 40 filtered x86/x64 EXEs
within six folder levels, requires confirmation, and always offers Browse;
common helper/redist files and DLLs are excluded. Shell fixtures cover discovery,
cancellation and resumption without rerunning setup. Native tests cover discovery
of pending records and preserving the environment in continuation arguments.

The Windows installation sheet now supports EXE/MSI setup files, an optional
destination folder, Mac-app creation and launch control. Recovery accepts the
installed EXE/folder directly. Fixtures cover MSI routing to the installer helper,
registration without launch, shortcut generation and early rejection of invalid
MSI/DLL inputs. Native tests cover argument propagation and optional fields.

Ports now also supports editing existing definitions without reinstalling.
CLI updates and the native Edit sheet share creation validation; staged saves
retain original settings on invalid input or write failure. Shell fixtures cover
EXE/architecture changes, renderer switching, clearing saved values, metadata
retention, failed writes, launching the edited definition, and rebuilding an app.
Native tests cover draft loading/clearing and capture the Edit sheet. Interactive
edit/retry and the resulting real-game launch remain part of the UI/game gates.

Port recovery now includes local game-file checks, Finder reveal and the selected
port's launch log. File checks report missing games/environments, EXE bitness
mismatches and x64 games in win32 prefixes; reports explicitly retain an untested
gameplay status. Tests verify checks do not create/change files. The native
Bottles list respects the same support/bottle-directory overrides as the CLI.

Shell regression tests cover port creation/build/launch with a fake runtime,
program-architecture propagation, arguments containing spaces and empty values,
literal wildcards, malformed quotes, Spock DLL placement and fallback overrides,
and structural game preflight. These fixtures do not run Windows games.

Before a release is called ready, record all of the following against the final
commit and artifact:

| Gate | Required evidence |
| --- | --- |
| Automated code checks | Full shell suite, debug/release Swift builds, and XCTest, including Ports directory overrides |
| Packaging | Built app release audit, expected architecture, and DMG smoke checks on macOS |
| UI/UX | Ports/Graphics before Steam setup; first port with/without Rosetta and Spock; minimum window size, light/dark, keyboard-only, VoiceOver and Reduce Motion; failed creation/retry and a pending Terminal job |
| 32-bit baseline | Actual x86 game in the intended WoW64 runtime: launch, menu, gameplay, save/load, exit/relaunch |
| Spock | Same game/settings against WineD3D, recording exact runtime/DLL versions and the loaded renderer; test missing-x86 fallback too |
| Distribution | Developer ID signature/notarization and fresh install/update verification for a public release |

macOS CI can establish compilation and packaging checks. It cannot establish
interactive accessibility or gameplay results. Linux shell checks cannot
establish any native UI or GPU compatibility result. Keep unperformed gates
explicitly pending rather than treating them as passed.

## Audit implementation follow-up

The upstream audit now has implemented junction reading, runtime diagnostics,
scoped process stopping, named-environment cloning, verified resumable downloads
and curated recipe review. See [UPSTREAM_IMPLEMENTATION.md](UPSTREAM_IMPLEMENTATION.md)
for boundaries and verification. Real SimCity 3000 Unlimited installation/gameplay,
32-bit runtime behavior, SpockD3D9 rendering and interactive accessibility remain
manual release gates; fixture success does not establish game compatibility.


Reset/delete follow-up adds scoped shutdown, non-following cleanup, mount/link
refusal and actionable partial-removal recovery. Existing confirmations remain;
port definitions and linked external folders are preserved. Bottles details exposes
Clone Environment before registration. Fixtures run on Linux and macOS CI; no
actual user environment is removed by validation.
