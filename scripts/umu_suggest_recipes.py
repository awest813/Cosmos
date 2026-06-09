#!/usr/bin/env python3
"""Map UMU/protonfix hints to Cosmos recipe IDs (deps and fixes)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Reuse protonfix parsing (same VERB_TO_RECIPE table).
_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "scripts"))

from protonfix_port_hint import VERB_TO_RECIPE, fetch_fix, parse_fix  # noqa: E402

def load_winemactricks_fixes(repo: Path, appid: str) -> list[str]:
    map_path = repo / "scripts" / "data" / "winemactricks-profile-map.json"
    if not map_path.is_file():
        return []
    data = json.loads(map_path.read_text(encoding="utf-8"))
    fixes: list[str] = []
    entry = (data.get("by_appid") or {}).get(appid) or {}
    fixes.extend(entry.get("fixes") or [])
    for _tid, spec in (data.get("by_tweak_id") or {}).items():
        if int(appid) in (spec.get("steam_appids") or []):
            for fix in spec.get("fixes") or []:
                if fix not in fixes:
                    fixes.append(fix)
    return fixes


def suggest_from_protonfix_body(body: str) -> dict[str, list[str]]:
    parsed = parse_fix(body)
    deps = list(parsed.get("suggested_dependencies") or [])
    fixes: list[str] = []
    for verb in parsed.get("winetricks_verbs") or []:
        recipe = VERB_TO_RECIPE.get(verb)
        if recipe and recipe not in deps:
            deps.append(recipe)
    return {"dependencies": deps, "fixes": fixes}


def suggest_for_appid(
    appid: str,
    *,
    repo: Path,
    offline: bool = False,
    fixture: Path | None = None,
) -> dict[str, list[str]]:
    deps: list[str] = []
    fixes: list[str] = load_winemactricks_fixes(repo, appid)

    body: str | None = None
    if fixture and fixture.is_file():
        body = fixture.read_text(encoding="utf-8", errors="replace")
    elif not offline:
        _resolved, body = fetch_fix(appid)

    if body:
        hit = suggest_from_protonfix_body(body)
        for dep in hit["dependencies"]:
            if dep not in deps:
                deps.append(dep)
        for fix in hit["fixes"]:
            if fix not in fixes:
                fixes.append(fix)

    # Validate recipes exist on disk.
    dep_dir = repo / "recipes" / "dependencies"
    fix_dir = repo / "recipes" / "fixes"
    deps = [d for d in deps if (dep_dir / f"{d}.recipe").is_file()]
    fixes = [f for f in fixes if (fix_dir / f"{f}.recipe").is_file()]

    return {"dependencies": deps, "fixes": fixes}


def main() -> int:
    parser = argparse.ArgumentParser(description="UMU/protonfix → Cosmos recipe suggestions")
    parser.add_argument("appid")
    parser.add_argument("--repo", default=str(_REPO))
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--fixture", help="Protonfix .py body fixture (tests)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    appid = args.appid.strip()
    if not appid.isdigit():
        print("appid must be numeric", file=sys.stderr)
        return 2

    fixture = Path(args.fixture) if args.fixture else None
    out = suggest_for_appid(
        appid,
        repo=Path(args.repo),
        offline=args.offline,
        fixture=fixture,
    )
    if args.json:
        print(json.dumps(out, indent=2))
        return 0

    for dep in out["dependencies"]:
        print(f"dep {dep}")
    for fix in out["fixes"]:
        print(f"fix {fix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
