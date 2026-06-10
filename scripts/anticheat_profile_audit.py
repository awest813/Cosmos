#!/usr/bin/env python3
"""Audit curated profiles against the anti-cheat blocklist."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SHIPPED_STORES = ("steam", "gog", "itch", "battlenet", "standalone")
AC_NOTE_RE = re.compile(r"anti[- ]?cheat|battleye|easy anti|eac|ricochet|blocked", re.I)


def load_blocklist(repo: Path) -> dict[str, dict]:
    path = repo / "scripts" / "data" / "anticheat-blocklist.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    return {str(k): v for k, v in (data.get("by_appid") or {}).items()}


def shipped_profiles(repo: Path) -> dict[str, Path]:
    profiles: dict[str, Path] = {}
    root = repo / "profiles"
    for store in SHIPPED_STORES:
        store_dir = root / store
        if not store_dir.is_dir():
            continue
        for path in sorted(store_dir.glob("*.yaml")) + sorted(store_dir.glob("*.yml")):
            text = path.read_text(encoding="utf-8")
            match = re.search(r"^steam_appid:\s*(\d+)\s*$", text, re.M)
            if match:
                profiles[match.group(1)] = path
    return profiles


def parse_scalar(text: str, key: str) -> str:
    match = re.search(
        rf"^{re.escape(key)}:\s*(.+)$",
        text,
        re.M,
    )
    if not match:
        return ""
    value = match.group(1).strip().strip('"').strip("'")
    return value


def parse_notes(text: str) -> str:
    if re.search(r"^notes:\s*>", text, re.M):
        block = re.search(r"^notes:\s*>\s*\n((?:  .+\n?)*)", text, re.M)
        if block:
            lines = [
                line[2:] if line.startswith("  ") else line
                for line in block.group(1).splitlines()
            ]
            return " ".join(lines).strip()
    return parse_scalar(text, "notes")


def audit(repo: Path) -> list[str]:
    errors: list[str] = []
    blocklist = load_blocklist(repo)
    profiles = shipped_profiles(repo)

    for appid, entry in blocklist.items():
        scope = entry.get("scope", "full")
        path = profiles.get(appid)
        if scope == "full":
            if path is None:
                errors.append(
                    f"missing blocked profile for {entry.get('title', appid)} ({appid})"
                )
                continue
            text = path.read_text(encoding="utf-8")
            status = parse_scalar(text, "status")
            if status != "blocked":
                errors.append(
                    f"{path.name}: appid {appid} must be status:blocked (got {status!r})"
                )
            notes = parse_notes(text)
            if not AC_NOTE_RE.search(notes):
                errors.append(f"{path.name}: blocked profile notes must mention anti-cheat")
        elif scope == "online_only":
            if path is None:
                continue
            text = path.read_text(encoding="utf-8")
            status = parse_scalar(text, "status")
            if status == "blocked":
                errors.append(
                    f"{path.name}: appid {appid} is online_only in blocklist but marked blocked"
                )
            notes = parse_notes(text)
            if not AC_NOTE_RE.search(notes):
                errors.append(
                    f"{path.name}: online_only anti-cheat title must warn in notes ({appid})"
                )

    full_ids = {appid for appid, entry in blocklist.items() if entry.get("scope") == "full"}
    for appid, path in profiles.items():
        text = path.read_text(encoding="utf-8")
        status = parse_scalar(text, "status")
        if status != "blocked":
            continue
        if appid not in full_ids:
            errors.append(
                f"{path.name}: status blocked but appid {appid} missing from blocklist full entries"
            )
            continue
        notes = parse_notes(text)
        if not AC_NOTE_RE.search(notes):
            errors.append(f"{path.name}: blocked profile notes must mention anti-cheat")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit profiles vs anti-cheat blocklist")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = audit(args.repo)
    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        print(f"FAIL: {len(errors)} anti-cheat audit error(s)", file=sys.stderr)
        return 1
    full = sum(1 for e in load_blocklist(args.repo).values() if e.get("scope") == "full")
    blocked = sum(
        1
        for p in shipped_profiles(args.repo).values()
        if parse_scalar(p.read_text(encoding="utf-8"), "status") == "blocked"
    )
    print(f"OK: anti-cheat audit passed ({blocked} blocked profiles, {full} full blocklist entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
