#!/usr/bin/env python3
"""Extract Steam library folder paths from libraryfolders.vdf using ValvePython/vdf."""
from __future__ import annotations

import sys
from pathlib import Path


def _paths_from_mapping(node: object, out: list[str]) -> None:
    if not isinstance(node, dict):
        return
    path = node.get("path")
    if isinstance(path, str) and path.strip():
        out.append(path.strip())
    for key, value in node.items():
        if key == "path":
            continue
        if isinstance(value, dict):
            _paths_from_mapping(value, out)


def library_paths_from_vdf_file(path: Path) -> list[str]:
    try:
        import vdf  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "python vdf package required: pip install vdf (ValvePython/vdf)"
        ) from exc

    data = vdf.load(path.open("r", encoding="utf-8", errors="replace"))
    root = data.get("libraryfolders") or data.get("LibraryFolders") or data
    paths: list[str] = []
    if isinstance(root, dict):
        _paths_from_mapping(root, paths)
    deduped: list[str] = []
    seen: set[str] = set()
    for item in paths:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <libraryfolders.vdf>", file=sys.stderr)
        return 2
    for line in library_paths_from_vdf_file(Path(sys.argv[1])):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
