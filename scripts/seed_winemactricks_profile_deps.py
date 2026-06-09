#!/usr/bin/env python3
"""Bulk-seed profile dependencies/fixes from winemactricks map + JSON."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

def slugify(tweak_id: str) -> str:
    s = tweak_id.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def load_map(repo: Path) -> dict[str, dict]:
    map_path = repo / "scripts" / "data" / "winemactricks-profile-map.json"
    json_path = repo / "third_party" / "winemactricks-json" / "winemactricks.json"
    data = json.loads(map_path.read_text(encoding="utf-8"))
    by_appid: dict[str, dict] = {
        str(k): {"dependencies": list(v.get("dependencies") or []), "fixes": list(v.get("fixes") or [])}
        for k, v in (data.get("by_appid") or {}).items()
    }

    for tweak_id, entry in (data.get("by_tweak_id") or {}).items():
        fixes = [slugify(tweak_id)] if not entry.get("fixes") else list(entry["fixes"])
        for appid in entry.get("steam_appids") or []:
            slot = by_appid.setdefault(str(appid), {"dependencies": [], "fixes": []})
            for fix in fixes:
                if fix not in slot["fixes"]:
                    slot["fixes"].append(fix)

    if json_path.is_file():
        wt = json.loads(json_path.read_text(encoding="utf-8"))
        for tweak in wt.get("tweaks") or []:
            appids = tweak.get("steam_appids") or tweak.get("steam_appid") or []
            if isinstance(appids, int):
                appids = [appids]
            if not appids:
                continue
            tid = tweak.get("id") or ""
            verb = tweak.get("winetricks")
            for appid in appids:
                slot = by_appid.setdefault(str(appid), {"dependencies": [], "fixes": []})
                if verb:
                    dep = slugify(tid) if (repo / "recipes" / "dependencies" / f"{slugify(tid)}.recipe").is_file() else verb
                    if dep not in slot["dependencies"]:
                        slot["dependencies"].append(dep)
                else:
                    fix = slugify(tid)
                    if fix not in slot["fixes"]:
                        slot["fixes"].append(fix)

    return by_appid


def recipe_exists(repo: Path, kind: str, recipe_id: str) -> bool:
    sub = "dependencies" if kind == "dependencies" else "fixes"
    return (repo / "recipes" / sub / f"{recipe_id}.recipe").is_file()


def parse_list_section(text: str, section: str) -> tuple[list[str], int, int]:
    """Return (items, start_line, end_line_exclusive)."""
    lines = text.splitlines()
    items: list[str] = []
    start = end = -1
    in_section = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == f"{section}:":
            in_section = True
            start = i
            continue
        if in_section:
            if stripped.startswith("- "):
                item = stripped[2:].strip().strip('"').strip("'")
                items.append(item)
            elif stripped and not stripped.startswith("#"):
                end = i
                break
    if in_section and end < 0:
        end = len(lines)
    return items, start, end


def merge_profile(repo: Path, path: Path, deps: list[str], fixes: list[str], dry_run: bool) -> bool:
    text = path.read_text(encoding="utf-8")
    if not re.search(r"^steam_appid:\s*\d+\s*$", text, re.M):
        return False

    changed = False
    for section, additions in (("dependencies", deps), ("fixes", fixes)):
        valid = [a for a in additions if recipe_exists(repo, section, a)]
        if not valid:
            continue
        existing, start, end = parse_list_section(text, section)
        merged = existing[:]
        section_changed = False
        for item in valid:
            if item not in merged:
                merged.append(item)
                section_changed = True
        if not section_changed:
            continue
        changed = True
        if start < 0:
            insert_at = text.find("\nnotes:")
            block = f"\n{section}:\n" + "".join(f"  - {x}\n" for x in merged)
            if insert_at >= 0:
                text = text[:insert_at] + block + text[insert_at:]
            else:
                text = text.rstrip() + "\n" + block
        else:
            new_lines = [f"{section}:"] + [f"  - {x}" for x in merged]
            lines = text.splitlines()
            text = "\n".join(lines[:start] + new_lines + lines[end:]) + "\n"

    if changed and not dry_run:
        path.write_text(text, encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed profile deps from winemactricks map")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--appid", help="Only seed one Steam App ID")
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]))
    args = parser.parse_args()

    repo = Path(args.repo)
    profiles = repo / "profiles" / "steam"
    by_appid = load_map(repo)
    updated = 0
    for path in sorted(profiles.glob("steam-*.yaml")):
        m = re.search(r"steam-(\d+)-", path.name)
        appid = m.group(1) if m else None
        if not appid:
            continue
        if args.appid and appid != args.appid:
            continue
        entry = by_appid.get(appid)
        if not entry:
            continue
        if merge_profile(repo, path, entry["dependencies"], entry["fixes"], args.dry_run):
            action = "would update" if args.dry_run else "updated"
            print(f"{action} {path.relative_to(repo)}")
            updated += 1

    print(f"done: {updated} profile(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
