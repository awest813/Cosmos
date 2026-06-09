#!/usr/bin/env python3
"""Extract Cosmos-portable hints from umu-protonfixes game scripts (reference only).

Does not copy GPL Python into the Cosmos repo — fetches at runtime/dev time and
prints JSON suggestions for profile/recipe updates.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

FIX_BASE = (
    "https://raw.githubusercontent.com/Open-Wine-Components/umu-protonfixes/"
    "master/gamefixes-steam/"
)

VERB_TO_RECIPE = {
    "vcrun2010": "vcrun2010",
    "vcrun2015": "vcrun2015",
    "vcrun2019": "vcrun2019",
    "vcrun2017": "vcrun2019",
    "vcrun2013": "vcrun2015",
    "vcrun2022": "vcrun2019",
    "d3dx9": "d3dx9",
    "d3dx9_43": "d3dx9",
    "d3dx11_43": "d3dx9",
    "dotnet48": "dotnet48",
    "dotnet462": "dotnet48",
    "dotnet35sp1": "dotnet48",
    "corefonts": "corefonts",
    "allfonts": "corefonts",
}


def fetch_fix(appid: str, seen: set[str] | None = None) -> tuple[str | None, str | None]:
    if seen is None:
        seen = set()
    if appid in seen:
        return None, None
    seen.add(appid)
    url = f"{FIX_BASE}{appid}.py"
    try:
        text = urllib.request.urlopen(url, timeout=20).read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError:
        return None, None
    text = text.strip()
    if text.endswith(".py") and "\n" not in text and len(text) < 24:
        resolved, body = fetch_fix(text[:-3], seen)
        return resolved or text[:-3], body
    return appid, text


def parse_fix(body: str) -> dict:
    tricks = re.findall(r"""protontricks\(\s*['"]([^'"]+)['"]""", body)
    for block in re.findall(r"protontricks\(\s*\[([^\]]+)\]", body):
        tricks.extend(re.findall(r"""['"]([^'"]+)['"]""", block))
    env = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r"""set_environment\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]*)['"]""", body
        )
    }
    exe = [
        {"from": m.group(1), "to": m.group(2)}
        for m in re.finditer(
            r"\([\"']([^\"']+\.exe)[\"']\s*,\s*[\"']([^\"']+\.exe)[\"']\)", body
        )
    ]
    deps: list[str] = []
    for verb in tricks:
        recipe = VERB_TO_RECIPE.get(verb)
        if recipe and recipe not in deps:
            deps.append(recipe)
    cosmos_env = {}
    for key, val in env.items():
        upper = key.upper()
        if upper in ("DXMT_CONFIG", "STEAM_GAME_ARGS", "COSMOS_BACKEND"):
            cosmos_env[upper] = val
    notes: list[str] = []
    if exe:
        pairs = ", ".join(f"{x['from']} → {x['to']}" for x in exe[:3])
        notes.append(
            "Protonfix reference (GPL, do not import scripts): replaces executables "
            f"({pairs}). On macOS, install script extenders in the prefix and launch "
            "the loader exe manually or via STEAM_GAME_ARGS when supported."
        )
    if tricks:
        unknown = [v for v in tricks if v not in VERB_TO_RECIPE]
        if unknown:
            notes.append(
                "Protonfix winetricks verbs without Cosmos recipes yet: "
                + ", ".join(sorted(set(unknown)))
            )
    return {
        "winetricks_verbs": sorted(set(tricks)),
        "environment": env,
        "exe_replacements": exe,
        "suggested_dependencies": deps,
        "suggested_env": cosmos_env,
        "suggested_notes": " ".join(notes),
    }


def find_profile(repo: Path, appid: str) -> str | None:
    profiles = repo / "profiles" / "steam"
    if not profiles.is_dir():
        return None
    for path in profiles.glob("steam-*.yaml"):
        text = path.read_text(encoding="utf-8")
        if re.search(rf"^steam_appid:\s*{appid}\s*$", text, re.M):
            return str(path.relative_to(repo))
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Protonfix → Cosmos port hints")
    parser.add_argument("appid", help="Steam App ID")
    parser.add_argument(
        "--repo",
        default=str(Path(__file__).resolve().parents[1]),
        help="Cosmos repo root",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON only")
    args = parser.parse_args()
    appid = args.appid.strip()
    if not appid.isdigit():
        print("appid must be numeric", file=sys.stderr)
        return 2

    resolved, body = fetch_fix(appid)
    repo = Path(args.repo)
    out = {
        "steam_appid": int(appid),
        "has_protonfix": bool(body),
        "fix_file": f"{appid}.py",
        "resolved_fix_file": f"{resolved}.py" if resolved else None,
        "cosmos_profile": find_profile(repo, appid),
    }
    if body:
        out.update(parse_fix(body))
    else:
        out.update(
            {
                "winetricks_verbs": [],
                "environment": {},
                "exe_replacements": [],
                "suggested_dependencies": [],
                "suggested_env": {},
                "suggested_notes": (
                    "No umu-protonfixes steam script found. Check "
                    "./cosmosdb.command lookup {appid} umu for UMU database entries."
                ).format(appid=appid),
            }
        )

    if args.json:
        print(json.dumps(out, indent=2))
        return 0

    print(f"Steam App ID: {appid}")
    print(f"Protonfix: {out['resolved_fix_file'] or 'not found'}")
    if out.get("cosmos_profile"):
        print(f"Cosmos profile: {out['cosmos_profile']}")
    if out.get("suggested_dependencies"):
        print("Suggested dependencies:", ", ".join(out["suggested_dependencies"]))
    if out.get("suggested_env"):
        print("Suggested env:", json.dumps(out["suggested_env"]))
    if out.get("exe_replacements"):
        print("Exe replacements:", out["exe_replacements"])
    if out.get("suggested_notes"):
        print("Notes:", out["suggested_notes"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
