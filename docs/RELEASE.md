# Cosmos release checklist

This checklist is for user-facing macOS builds. The primary release artifact is
the Apple Silicon disk image:

```bash
COSMOS_BUILD_ARCHS=arm64 DMG_NAME=Cosmos-macos-arm64.dmg scripts/build_dmg.command
```

The output is `build/Cosmos-macos-arm64.dmg`.

## Prerequisites

- Apple Silicon Mac or GitHub Actions `macos-15-xlarge` runner.
- Xcode or Xcode Command Line Tools with Swift 5.9+.
- Developer ID Application certificate for public releases.
- Apple notarization credentials:
  - `APPLE_ID`
  - `APPLE_TEAM_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`, or notary API key settings

## Local signed build

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="app-specific-password"

COSMOS_BUILD_ARCHS=arm64 DMG_NAME=Cosmos-macos-arm64.dmg scripts/build_dmg.command
```

`scripts/build_dmg.command` signs the app before packaging, signs the DMG, submits
it to Apple notary service, and staples the notarization ticket when credentials
are present.

## Verify before publishing

```bash
APP_BUNDLE=build/Cosmos.app COSMOS_EXPECTED_APP_ARCHS=arm64 scripts/audit_release.sh
codesign --verify --deep --strict --verbose=2 build/Cosmos.app
spctl --assess --type execute --verbose=4 build/Cosmos.app
spctl --assess --type open --context context:primary-signature --verbose=4 build/Cosmos-macos-arm64.dmg
shasum -a 256 build/Cosmos-macos-arm64.dmg > build/Cosmos-macos-arm64.dmg.sha256
```

## User smoke test

1. Download `Cosmos-macos-arm64.dmg` on an Apple Silicon Mac.
2. Open the disk image and drag Cosmos into Applications.
3. Launch Cosmos from Applications.
4. Confirm the setup checklist shows Rosetta status, Wine runtime status, and the
   first-time setup actions.
5. Run a fixture/offline build first when testing release mechanics:

```bash
COSMOS_OFFLINE_FIXTURE=1 COSMOS_BUILD_ARCHS=arm64 DMG_NAME=Cosmos-macos-arm64.dmg scripts/build_dmg.command
```
