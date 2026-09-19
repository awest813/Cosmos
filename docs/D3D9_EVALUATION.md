# D3D9 backend evaluation

Reviewed September 7, 2026. “SpockDX9” is interpreted here as the existing **SpockD3D9** integration. “d9mt” refers to **neo773/d9mt**; similarly named forks are distinct projects and should not share an implementation contract.

## Recommendation

**Keep SpockD3D9 experimental and make it testable now. Track d9mt for an isolated proof of concept, but do not add it as a normal backend or default yet.** This is an engineering recommendation, not a comparative performance finding. Cosmos has not benchmarked either backend on this machine.

[SpockD3D9 upstream](https://github.com/awest813/SpockD3D9) distinguishes its native macOS renderer from experimental Windows PE hosting. Cosmos needs the PE DLL route for Windows games. The native library's success does not establish retail Windows-game compatibility.

[neo773/d9mt upstream](https://github.com/neo773/d9mt) describes direct D3D9-to-Metal translation, with testing limited to GTA IV. It targets Apple Silicon/macOS 14+ and requires winemetal plus a native d9mtmetal companion, the Metal compiler, mingw and shader tools. It is not just another d3d9.dll folder. Its documented build/deployment workflow is centered on CrossOver. Reported upstream performance is not a Cosmos benchmark.

## What would justify adding d9mt?

- A pinned, reproducible build against Cosmos's Wine and winemetal versions, installed inside a dedicated test environment without altering another application's bundle.
- Clear redistribution terms for the project and bundled dependencies before packaging.
- Repeatable rendering, save/load, exit/relaunch, input/audio and windowing results on several D3D9 engines—not just one title.
- Evidence of a meaningful compatibility or frame-time improvement over the same game's WineD3D and Spock runs at identical settings.
- Explicit host/OS and game-architecture gating, companion-library validation, and safe rollback.

If those gates pass, add an opt-in experimental backend with its own validator, runtime manifest entry, tests, and support documentation. Until then, no selectable d9mt option is exposed: choosing it would imply an integration Cosmos does not yet have.

## Fixes delivered for Spock testing

- Check the DLL's actual x86/x64 PE architecture rather than accepting any PE DLL in either folder.
- Reject a mixed folder containing an invalid architecture instead of passing because its other DLL is valid.
- Merge D3D9 load-order settings without losing unrelated overrides or leaving conflicting D3D9 entries.
- Invalidate UI validation when the path changes and revalidate before applying it.
- Apply the Spock path/backend to the selected named environment when one is selected; otherwise save to the default environment. Backend selection happens only after path saving succeeds.
- Label file validation honestly and explain missing 32-bit/64-bit coverage.
- Add a read-only preflight, a test-details template, and the [real-game test procedure](REAL_GAME_TESTING.md).

## Evidence and limitations

The local audit found no default Wine runtime, initialized prefix, Spock DLLs, or Spock build tools. Automated checks use controlled file fixtures and do not prove GPU rendering. Real game results remain **untested**. No new runtime was downloaded or installed during this work.


Validation completed: release app build; Spock PE-architecture and override-merging regressions; graphics helper checks; five direct-launch path checks; two preflight test cases covering missing files, architecture mismatch, untested status, and game-local DLL warnings. Full XCTest and real GPU/gameplay tests remain unverified. Spock build outputs are validated before publishing, and source builds now use the writable Application Support cache.
