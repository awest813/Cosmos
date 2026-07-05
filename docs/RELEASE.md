# Cosmos release checklist

This checklist is for user-facing macOS builds. The primary release artifact is
the Apple Silicon disk image:

```bash
COSMOS_BUILD_ARCHS=arm64 DMG_NAME=Cosmos-macos-arm64.dmg scripts/build_dmg.command
```

The output is `build/Cosmos-macos-arm64.dmg`.

## Prerequisites

- Apple Silicon Mac or GitHub Actions `macos-15` runner.
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

## Producing a GitHub release

`.github/workflows/release.yml` builds and publishes `Cosmos-macos-arm64.dmg` on
the standard Apple Silicon `macos-15` runner. It can be triggered two ways:

- **Tag push** — push a `v*` tag whose version matches `VERSION`:

  ```bash
  git tag -a "v$(tr -d '[:space:]' < VERSION)" -m "Cosmos $(cat VERSION)"
  git push origin "v$(tr -d '[:space:]' < VERSION)"
  ```

- **Manual dispatch** — from the repository **Actions → Release → Run workflow**
  (or `gh workflow run release.yml`). The version is read from `VERSION`, and the
  matching `v<VERSION>` tag is created automatically on the built commit. This
  lets GitHub produce the release without a local tag push.

Both paths run the same job and require `VERSION` to be authoritative for the
release number.

Release builds set `COSMOS_RELEASE_BUILD=1`; that forces the DMG builder to reject
fixture offline runtime bundles. The tagged workflow therefore downloads and
packages the real Wine + DXMT runtime from `runtime/cosmos-runtime.json`. Fixture
runtime bundles (`COSMOS_OFFLINE_FIXTURE=1`) are only for CI smoke tests and local
release-mechanics checks.

For a Gatekeeper-clean release, configure all of these repository secrets:

- `APPLE_CERTIFICATE_BASE64` — base64-encoded Developer ID Application `.p12`
- `APPLE_CERTIFICATE_PASSWORD` — password for that `.p12`
- `DEVELOPER_ID_APPLICATION` — signing identity name, for example
  `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

If any of those secrets are missing, the release workflow deliberately falls back
to an ad-hoc signed preview DMG instead of attempting a partial signing run.

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

Do not set `COSMOS_OFFLINE_FIXTURE=1` for a user-facing tagged release.
