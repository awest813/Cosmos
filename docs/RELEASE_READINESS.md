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
