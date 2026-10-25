#!/usr/bin/env python3
"""Read-only structural checks for a manual game test; never launches or installs."""
import argparse
import hashlib
import json
import os
import platform
import struct
from datetime import datetime, timezone
from pathlib import Path


def pe_kind(path):
    try:
        with Path(path).open('rb') as stream:
            header = stream.read(64)
            if len(header) != 64 or header[:2] != b'MZ':
                return None
            offset = struct.unpack_from('<I', header, 60)[0]
            stream.seek(offset)
            coff = stream.read(24)
            if len(coff) != 24 or coff[:4] != b'PE\0\0':
                return None
            machine = struct.unpack_from('<H', coff, 4)[0]
            flags = struct.unpack_from('<H', coff, 22)[0]
            arch = {0x14c: 'x86', 0x8664: 'x64'}.get(machine)
            return (arch, bool(flags & 0x2000)) if arch else None
    except (OSError, ValueError, struct.error):
        return None


def file_sha256(path):
    if path is None:
        return None
    try:
        digest = hashlib.sha256()
        with Path(path).open('rb') as stream:
            for chunk in iter(lambda: stream.read(65536), b''):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def prefix_architecture(prefix):
    try:
        with (prefix / 'system.reg').open(encoding='utf-8', errors='replace') as stream:
            for line in stream.read(4096).splitlines():
                if line in ('#arch=win32', '#arch=win64'):
                    return line.removeprefix('#arch=')
    except OSError:
        pass
    return 'unknown'


def inspect(exe, prefix, wine, backend, spock_root=None, moltenvk=None):
    exe, prefix, wine = Path(exe).expanduser(), Path(prefix).expanduser(), Path(wine).expanduser()
    checks = []

    def check(name, passed, detail):
        checks.append({'check': name, 'passed': bool(passed), 'detail': detail})

    kind = pe_kind(exe)
    check('game_executable', kind is not None and not kind[1], str(exe))
    check('wine_executable', wine.is_file() and os.access(wine, os.X_OK), str(wine))
    check('initialized_prefix', (prefix / 'system.reg').is_file(), str(prefix))
    prefix_arch = prefix_architecture(prefix)
    check('prefix_architecture', not (prefix_arch == 'win32' and kind and kind[0] == 'x64'),
          '32-bit prefix; 64-bit games require a 64-bit/WoW64 prefix' if prefix_arch == 'win32'
          else f'Prefix architecture: {prefix_arch}; runtime WoW64 support is not verified')
    dll = None
    if backend == 'spockd3d9':
        arch = kind[0] if kind else None
        candidates = {
            'x86': ['x86/d3d9.dll', 'build-pe-d3d9-x86/d3d9.dll', 'd3d9-x86.dll'],
            'x64': ['x64/d3d9.dll', 'build-pe-d3d9/d3d9.dll', 'd3d9.dll'],
        }.get(arch, [])
        if spock_root:
            root = Path(spock_root).expanduser()
            dll = next((root / name for name in candidates if (root / name).is_file()), None)
        check('matching_spock_dll', dll is not None and pe_kind(dll) == (arch, True),
              str(dll) if dll else 'No DLL found for the game architecture')
        check('moltenvk_file', moltenvk is not None and Path(moltenvk).expanduser().is_file(),
              str(moltenvk) if moltenvk else 'Supply --moltenvk with the library used by this Wine runtime')
    local_dll = exe.parent / 'd3d9.dll'
    warnings = ['Passing these file checks does not prove runtime loading, rendering, or compatibility.']
    if kind and kind[0] == 'x86' and prefix_arch != 'win32':
        warnings.append('This 32-bit game needs a Wine runtime with WoW64 support. A 64-bit Mac or Wine binary alone does not establish 32-bit game support. Use the matching x86 graphics DLL; do not force WINEARCH=win32 on a WoW64-only runtime.')
    if local_dll.is_file():
        warnings.append('The game folder contains d3d9.dll. It may take precedence over the prefix DLL; record its origin and verify the loaded module.')
    return {
        'schema_version': 1,
        'created_at': datetime.now(timezone.utc).isoformat(),
        'host': {'architecture': platform.machine(), 'macos': platform.mac_ver()[0]},
        'game_executable': str(exe), 'game_architecture': kind[0] if kind else 'unknown',
        'prefix': str(prefix), 'prefix_architecture': prefix_arch, 'backend_requested': backend,
        'spock_sha256': file_sha256(dll),
        'preflight_passed': all(item['passed'] for item in checks),
        'game_result': 'untested', 'checks': checks, 'warnings': warnings,
        'observations': {'backend_loaded': None, 'cold_launch': None, 'menu': None,
                         'gameplay_15_minutes': None, 'save_load': None, 'exit_relaunch': None,
                         'resolution': None, 'graphics_preset': None, 'average_fps': None,
                         'one_percent_low_fps': None, 'visual_issues': None},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True, help='Installed game executable, not Steam.exe')
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--wine', required=True, help='Wine executable used by this environment')
    parser.add_argument('--backend', choices=['recommended', 'dxmt', 'wined3d', 'spockd3d9'], default='recommended')
    parser.add_argument('--spock-root')
    parser.add_argument('--moltenvk')
    args = parser.parse_args()
    report = inspect(args.exe, args.prefix, args.wine, args.backend, args.spock_root, args.moltenvk)
    print(json.dumps(report, indent=2))
    return 0 if report['preflight_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
