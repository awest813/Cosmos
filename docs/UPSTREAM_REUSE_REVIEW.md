# Launcher and Wine-tool reuse review

Reviewed October 25, 2026 against Cosmos `15d74918`. “Sujo” is treated as
[Soju](https://github.com/BCD1210/soju), the launcher already referenced in Cosmos.
This is a source/architecture review. Candidate functionality has not been
integrated or game-tested by this review.

The strongest next step is to connect selected Highball/Vermut components to
Cosmos's existing installation, filesystem and repair flows. Both source trees
are already vendored, but their presence does not mean the Cosmos app calls them.
Keep Sikarugir-style per-game Ports as the main experience.

## What can be used

| Project | Useful material | Cosmos status and decision |
| --- | --- | --- |
| Whisky | Bottle configuration, pinned programs, removable-volume handling and running-process UI | GPLv3-family source. The repository is archived and its README says unmaintained. Use focused UX/model references; keep the current runtime rather than adopting its CrossOver 22.1.1 baseline. Much of the basic bottle/port UI already exists. |
| Moonshine | Direct executable launch, executable working directory and useful crash/module logs | GPLv3-family source. These behaviors are already implemented independently in Cosmos. Its Wine Staging 11.2 installer is behind Cosmos's 11.8 pin. Review logging improvements selectively; replace offset-only OpenGL patch assumptions with build-specific validation before expanding patch use. |
| Soju | Complete-prefix APFS cloning, per-store environments, input/focus fixes and store launch diagnostics | GPLv3-family source. AVX, write-copy, GPTK layout and Battle.net seeding behaviors already exist independently in Cosmos. Best new candidates are complete-prefix clone UX and bounded store-specific repairs. Its Chromium/custom-frame switches require its patched engine; setting those variables on stock Wine is not an implementation. |
| Highball | Read-only junction/reparse-point following, engine integrity, resumable downloads, prefix process inspection and recipe requirements | GPLv3 source already vendored at `bbada878`. Adapt selected helpers. Upstream has changed since that snapshot: its integrity check now notices a builtin DLL missing from either architecture half; the vendored version accepts a copy in either half. Reconcile this before adapting it. |
| Vermut | Prefix-owned process termination, non-following uninstall traversal, path ownership checks, bounded process waits and pipe draining | MIT source already vendored; reviewed upstream still matches the vendored commit. Best near-term process/cleanup reference. Replace Vermut-specific identifiers, ownership rules and managed paths with Cosmos's; do not copy those defaults verbatim. CosmosCommandRunner already drains output before waiting, so duplicating that runner adds little. |
| Sikarugir | Wrapper UX, combined renderer defaults, configuration and engine-selection concepts | Mixed component licensing. Main README points to separate LGPL-2.1 Configure sources and explicitly distinguishes newer Creator/Launcher components. Reuse verified FOSS components individually; the main distribution is not a blanket LGPL grant. Check its host/renderer requirements independently of Cosmos's minimum OS. |
| Heroic | Store adapters, save-path resolution, cloud-save UX and download queue architecture | GPLv3 source; macOS-relevant code exists. Prefer building on the existing Legendary integration and adding store-specific adapters. Save sync needs conflict/restore UX and store authentication; it is a later step than reliable local installation. Electron/TypeScript services are not drop-in Swift components. |
| Lutris | Declarative installer stages, file/dependency prompts, reusable installer tasks and registry/prefix utilities | GPLv3 source. Adapt a small reviewed task model to Cosmos profiles/recipes; GTK/GObject and Linux runner integration need replacement. Check the license/provenance of community installer data separately from the application. |
| Bottles | Environment checkpoints, backup/restore workflow, dependency management and task cancellation | GPLv3 source, with Linux/GTK and its FVS dependencies. Borrow checkpoint semantics and exclusion/restore tests, then implement a Mac-compatible storage backend. A full application transplant is unnecessary. |
| Winetricks | Dependency verbs, known installer workarounds and prerequisite repair | LGPL-2.1-or-later script. Cosmos already invokes it externally and imports dependency recipes. Improve dependency history and recipe selection rather than importing another full verb engine. Downloaded dependency payloads retain their own terms. |
| Highball DB | Curated game/store requirements, recipes, engine constraints and compatibility notes | Already vendored. Curated recipes/reports are CC0; `db/derived` predictions are ODbL; anti-cheat data retains a separate MIT notice. Import curated records through a provenance-preserving adapter, and keep upstream reports distinct from Cosmos-tested results. |

## Highest-value implementation order

### 1. Filesystem junctions and 32-bit runtime diagnostics

**Sources:** Highball's
[WineReparsePoint.swift](https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/WineReparsePoint.swift)
and [EngineIntegrity.swift](https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/EngineIntegrity.swift).

Highball documents Wine junction stubs carrying `user.WINEREPARSE` extended
attributes. Wine can follow these while a Mac-side `fileExists` check cannot.
Cosmos's new resolver currently handles POSIX links and case lookup, not these
reparse buffers. This can make a valid installed game appear missing.

Adapt the decoder and read-only follower to `wine_filesystem` and native file
checks. Route targets through Cosmos's actual drive mappings: Highball's C:/Z:
assumptions must not regress the new remapped-drive behavior. Do not convert
Windows junctions into Mac symlinks; upstream explains how that broke EA repair.
Do not invoke its legacy dematerialization/migration code on Cosmos prefixes.

Then distinguish missing runtime builtins from game-specific missing libraries.
Use the actual game bitness and installed engine architecture/layout; do not
assume every WoW64 runtime stores a second complete DLL tree. The reviewed
upstream both-halves change is valuable evidence, not a universal layout rule.

**Acceptance:** synthetic junction buffers/xattrs, malformed/cyclic targets,
mapped C:/D:/Z:, relative targets, missing files, and read-only behavior; x86/x64
builtin fixtures including a missing x86 copy with the x64 copy still present.
Real Wine 11.8 junction behavior remains a separate validation step.

### 2. Prefix-scoped process control and cleanup

**Sources:** Vermut's
[PrefixProcessTerminator.swift](https://github.com/Contessafry/Vermut/blob/3ad9649ee0ff88812052af3672992dfa354c1892/Sources/CaskLauncherCore/PrefixProcessTerminator.swift),
[UninstallPathPolicy.swift](https://github.com/Contessafry/Vermut/blob/3ad9649ee0ff88812052af3672992dfa354c1892/Sources/CaskLauncherCore/UninstallPathPolicy.swift)
and [ProcessPipe.swift](https://github.com/Contessafry/Vermut/blob/3ad9649ee0ff88812052af3672992dfa354c1892/Sources/CaskLauncherCore/ProcessPipe.swift).

Current Cosmos shutdown helpers combine a prefix-specific wineserver with
command-line regex matching. Replace regex ownership inference with tested
prefix/executable/PID ownership and bounded escalation. Reuse the ownership and
timeout design, adapting the large Vermut module's PathManager/GameStore coupling.
Use non-following traversal for size accounting, export and deletion; a Z: link
to `/` must stay a link rather than turning into a recursive host traversal.

**Acceptance:** two simultaneous Cosmos environments, native Steam, a foreign
Wine app, paths with spaces/regex characters, stale/reused PIDs, missing environment
variables, timeout handling, and symlinks to external folders. No live processes
should be stopped by the review or fixture tests.

### 3. Complete-environment clone and restore

**Sources:** Soju's
[setup-bottle.sh](https://github.com/BCD1210/soju/blob/43ed224336cdffdba9dc4b47aa858a5273eb0838/scripts/setup-bottle.sh)
and Bottles' [backup](https://github.com/bottlesdevs/Bottles/blob/40399cdb0abf6fceebe8663fc88826c9b15d4d5f/bottles/backend/managers/backup.py)
and [versioning](https://github.com/bottlesdevs/Bottles/blob/40399cdb0abf6fceebe8663fc88826c9b15d4d5f/bottles/backend/managers/versioning.py) managers.

Clone the registry, drive links and Windows data together; copying only a game's
folder can lose store registrations and dependencies. Add Cosmos metadata and
installation state, preserving extended attributes and relative links. APFS
copy-on-write is an optimization; provide a regular-copy fallback. Stop only the
target environment before taking a consistent snapshot. External drive targets
need an explicit backup scope; cloning their links does not copy external saves.

**Acceptance:** initialized/uninitialized prefixes, non-APFS destination, failed
copy with original intact, xattrs/junctions, disconnected drives, paths outside
managed storage and restoration into a new environment without overwriting an
existing one. Only then add pre-repair checkpoints.

### 4. Reliable component downloads and curated recipes

**Sources:** Highball's
[DownloadResume.swift](https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/DownloadResume.swift),
its engine download caller, and the separately licensed Highball DB recipes.

Cosmos has manifest-driven component downloads, but retries generally restart
the download. Adapt Range/If-Range/ETag decisions and verify Content-Range and the
pinned artifact hash before activating a staged runtime. Test HTTP 200/206/416,
changed ETags, interrupted/corrupt partials and atomic activation. Runtime
version changes still require the existing Wine-gap and gameplay gates.

Translate compatible curated requirements into Cosmos recipes with source revision,
engine/OS/architecture constraints and original test provenance. Do not bulk-copy
upstream “works” ratings into Cosmos's own game-test status. Heroic-style store
downloads/cloud saves and a larger Lutris-like installer task model can follow.

## Existing work to keep

- Cosmos's installer/port sheets, Windows filesystem resolver and Sikarugir-style
  combined renderer model already cover much of the shared launcher UX.
- Moonshine-inspired direct launches, executable working directories, crash notes
  and detailed Wine logging are already independently implemented.
- Soju-inspired AVX, write-copy, GPTK loader layout and Battle.net signature seeding
  already exist. Runtime patches such as custom Chromium flags, focus handling
  and IME fixes need a compatible engine build and regression testing.
- CosmosCommandRunner already drains its combined output pipe while the child
  runs. Use Vermut's pipe pattern for any remaining blocking helpers, not a duplicate
  command runner.
- Keep the current runtime pin during this review. A launcher fork's engine,
  architecture support or game claims do not establish Cosmos compatibility.

## License and provenance boundaries

Cosmos can distribute a GPLv3 combined application using compatible GPLv3 code,
preserving upstream source, notices and obligations. MIT/LGPL components retain
their own notices and applicable terms. Check per-file and dependency terms
before extraction. The initial review imported no code. The subsequent implementation adapts the
patterns below with per-file attribution; see [UPSTREAM_IMPLEMENTATION.md](UPSTREAM_IMPLEMENTATION.md).

Sikarugir's [main README](https://github.com/Sikarugir-App/Sikarugir/blob/9bfd1b8292747687266462ab6e2fe1561d14a730/README.md)
distinguishes LGPL Configure from newer Creator/Launcher components. Its verified
[FOSS source license](https://github.com/Sikarugir-App/Sikarugir-foss-sources/blob/4be1b048f8df14b073a6e39e8245bbb52c6a71c0/LICENSE)
does not grant rights to every file in the main distribution.

Highball DB's own notices distinguish
[CC0 recipes](https://github.com/gauthierpiarrette/highball-db/blob/b83867ab2f0d218c320ae8741b65faac74281335/recipes/LICENSE),
[ODbL derived predictions](https://github.com/gauthierpiarrette/highball-db/blob/b83867ab2f0d218c320ae8741b65faac74281335/db/derived/LICENSE)
and [MIT-derived anti-cheat data](https://github.com/gauthierpiarrette/highball-db/blob/b83867ab2f0d218c320ae8741b65faac74281335/db/anticheat.LICENSE).
The existing Cosmos vendor tree already contains these separate notices.

Apple D3DMetal and retail CrossOver application/engine distributions are separate
from launcher source grants. Buildable, published Wine source can be evaluated
under its applicable license; copying a retail bundle is a different action.

## Reviewed upstream revisions

Each hash is a point-in-time source reference, not a proposed runtime upgrade.

| Repository | Reviewed commit |
| --- | --- |
| Whisky-App/Whisky | `fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8` (archived) |
| ybmeng/moonshine | `03a8195a39726f39d989c80541746f9dae14553a` |
| BCD1210/soju | `43ed224336cdffdba9dc4b47aa858a5273eb0838` |
| gauthierpiarrette/highball | `1512223fff145eae3b4c9fb588edf86758bc756b` |
| Contessafry/Vermut | `3ad9649ee0ff88812052af3672992dfa354c1892` |
| Sikarugir-App/Sikarugir | `9bfd1b8292747687266462ab6e2fe1561d14a730` |
| Sikarugir-App/Sikarugir-foss-sources | `4be1b048f8df14b073a6e39e8245bbb52c6a71c0` |
| Heroic-Games-Launcher/HeroicGamesLauncher | `509a34feea8541b73c928e289f2cf262d432db4a` |
| lutris/lutris | `1f32fe0e46e2a5d92fad9db2846c7cb7becd20c3` |
| bottlesdevs/Bottles | `40399cdb0abf6fceebe8663fc88826c9b15d4d5f` |
| Winetricks/winetricks | `f3890f670867b5ffbc3938726db45c0f7d16c8ba` |
| gauthierpiarrette/highball-db | `b83867ab2f0d218c320ae8741b65faac74281335` |
