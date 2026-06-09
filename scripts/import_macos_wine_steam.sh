#!/usr/bin/env bash
# Import macos-wine-steam merlot_configs into Cosmos YAML profile drafts.
# Upstream: third_party/macos-wine-steam/ (MIT, ByMedion/macos-wine-steam)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/third_party/macos-wine-steam/merlot_configs"
DRAFTS="${ROOT}/profiles/drafts"
SYNC=0 DRY_RUN=0 MERGE=0

usage() {
  cat <<'EOF'
Import macos-wine-steam *.conf presets into Cosmos YAML profiles.

Usage: scripts/import_macos_wine_steam.sh [options]

Options:
  --sync        Download latest merlot_configs from GitHub before import.
  --write-drafts  Write profiles/drafts/steam-<appid>-<slug>.yaml (default).
  --merge       Merge env/backend hints into existing profiles/steam/*.yaml.
  --dry-run     Print actions without writing files.
  -h, --help    Show this help.
EOF
}

MODE="drafts"
while (($#)); do
  case "$1" in
    --sync) SYNC=1; shift ;;
    --write-drafts) MODE="drafts"; shift ;;
    --merge) MODE="merge"; MERGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if (( SYNC )); then
  mkdir -p "${VENDOR}"
  echo "Syncing merlot_configs from upstream..."
  for f in binding-of-isaac.conf steam.conf template.conf.example; do
    curl -fsSL \
      "https://raw.githubusercontent.com/ByMedion/macos-wine-steam/main/merlot_configs/${f}" \
      -o "${VENDOR}/${f}"
  done
fi

[[ -d "${VENDOR}" ]] || { echo "Missing ${VENDOR}" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

python3 - "${ROOT}" "${VENDOR}" "${DRAFTS}" "${MODE}" "${DRY_RUN}" <<'PY'
import json
import re
import sys
from pathlib import Path

root, vendor, drafts_dir, mode, dry = sys.argv[1:6]
dry_run = dry == "1"
vendor_path = Path(vendor)
profiles_steam = Path(root) / "profiles" / "steam"
drafts_path = Path(drafts_dir)

CONF_KEYS = {
    "COSMOS_BACKEND": "recommended_backend",
    "WINE_RETINA_MODE": "settings.retina",
    "WINDOWS_VERSION": "settings.windows_version",
}
ENV_KEYS = {"DXMT_CONFIG", "STEAM_GAME_ARGS", "WINEDLLOVERRIDES", "DLL_OVERRIDE"}


def slugify(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def parse_conf(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    data: dict = {"env": {}, "run_env_names": []}
    in_run = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("RUN_ENV_NAMES=("):
            in_run = True
            continue
        if in_run:
            if line == ")":
                in_run = False
            else:
                key = line.strip().rstrip(")")
                data["run_env_names"].append(key)
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip('"')
        if key == "STEAM_GAME_ID":
            data["steam_appid"] = val
        elif key == "APP_NAME":
            data["app_name"] = val.replace(" (Merlot)", "").replace(" (Cosmos)", "")
        elif key in CONF_KEYS:
            data[CONF_KEYS[key]] = val
        elif key in ENV_KEYS or key in data.get("run_env_names", []):
            data["env"][key] = val
    return data


def yaml_for_conf(conf: Path, parsed: dict) -> str:
    appid = parsed.get("steam_appid")
    if not appid or not str(appid).isdigit():
        raise ValueError(f"{conf.name}: missing STEAM_GAME_ID")
    name = parsed.get("app_name") or f"Steam App {appid}"
    slug = slugify(name)
    profile_id = slug.replace("-", "_")
    backend = parsed.get("recommended_backend", "dxmt")
    if backend == "gptk":
        backend = "d3dmetal"
    retina = parsed.get("settings.retina", "0")
    retina_bool = "false" if retina in ("0", "false", "") else "true"
    winver = parsed.get("settings.windows_version", "win10")
    lines = [
        f"# Generated from macos-wine-steam/{conf.name} — review before merging",
        f"id: {profile_id}",
        f'name: "{name}"',
        "store: steam",
        f"steam_appid: {appid}",
        "status: playable",
        f"recommended_backend: {backend}",
        "wine_version: cosmos-stable",
        "settings:",
        f"  retina: {retina_bool}",
        f"  windows_version: {winver}",
    ]
    if parsed.get("env"):
        lines.append("  env:")
        for k, v in sorted(parsed["env"].items()):
            lines.append(f'    {k}: "{v}"')
    lines.append(
        f'notes: "Imported from macos-wine-steam/{conf.name}. '
        f'Validate with ./profile.command validate."'
    )
    return "\n".join(lines) + "\n", appid, slug


def merge_into_profile(profile: Path, parsed: dict) -> bool:
    text = profile.read_text(encoding="utf-8")
    changed = False
    env = parsed.get("env") or {}
    for key, val in env.items():
        pattern = rf"^    {re.escape(key)}:.*$"
        repl = f'    {key}: "{val}"'
        if re.search(pattern, text, re.M):
            if repl not in text:
                text = re.sub(pattern, repl, text, count=1, flags=re.M)
                changed = True
        elif "  env:" in text:
            text = text.replace("  env:\n", f"  env:\n    {key}: \"{val}\"\n", 1)
            changed = True
    backend = parsed.get("recommended_backend")
    if backend and backend != "gptk":
        if re.search(r"^recommended_backend:.*$", text, re.M):
            new = f"recommended_backend: {backend}"
            if new not in text:
                text = re.sub(r"^recommended_backend:.*$", new, text, count=1, flags=re.M)
                changed = True
    if changed and not dry_run:
        profile.write_text(text, encoding="utf-8")
    return changed


created = merged = skipped = 0
SKIP_NAMES = {"steam.conf"}

for conf in sorted(vendor_path.glob("*.conf")):
    if conf.name in SKIP_NAMES:
        print(f"skip {conf.name}: bottle defaults, not a game preset")
        skipped += 1
        continue
    try:
        parsed = parse_conf(conf)
    except ValueError as exc:
        print(f"skip {conf.name}: {exc}")
        skipped += 1
        continue
    body, appid, slug = yaml_for_conf(conf, parsed)
    target = profiles_steam / f"steam-{appid}-{slug}.yaml"
    if mode == "merge":
        if target.exists():
            if merge_into_profile(target, parsed):
                print(f"merged {conf.name} -> {target}")
                merged += 1
            else:
                print(f"unchanged {target}")
        else:
            print(f"skip merge {conf.name}: no profile at {target}")
            skipped += 1
        continue
    out = drafts_path / f"steam-{appid}-{slug}.yaml"
    if dry_run:
        print(f"would write {out}")
        continue
    drafts_path.mkdir(parents=True, exist_ok=True)
    out.write_text(body, encoding="utf-8")
    print(f"wrote {out}")
    created += 1

print(f"import complete: created={created} merged={merged} skipped={skipped}")
PY
