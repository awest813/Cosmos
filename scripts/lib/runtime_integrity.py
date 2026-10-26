"""Read-only, architecture-aware Wine builtin diagnostics.

Builtin allowlist and log classification adapted from Highball EngineIntegrity,
GPL-3.0, Highball contributors, revision 1512223fff145eae3b4c9fb588edf86758bc756b.
https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/EngineIntegrity.swift
"""
import argparse
import json
import re
from pathlib import Path

BUILTINS = set('ntdll kernel32 kernelbase user32 gdi32 advapi32 ole32 oleaut32 combase shell32 shlwapi shcore rpcrt4 msvcrt ws2_32 setupapi version imm32 comctl32 comdlg32 winmm win32u sechost crypt32'.split())
BUILTINS = {name + '.dll' for name in BUILTINS}


def diagnose(binary, output, architecture=None):
    names = list(dict.fromkeys(name.lower() for name in re.findall(r'import_dll[^\n]*?Library\s+([A-Za-z0-9_.+-]+)[^\n]*?not found', output, re.I)))
    builtin_names = [name for name in names if name in BUILTINS]
    library = Path(binary).resolve().parent.parent / 'lib' / 'wine'
    wanted = {'win32': ['i386-windows'], 'win64': ['x86_64-windows', 'aarch64-windows']}.get(architecture, ['i386-windows', 'x86_64-windows', 'aarch64-windows'])
    present = [library / name for name in wanted if (library / name).is_dir()]
    missing = []
    for directory in present:
        for name in builtin_names:
            # Missing in either installed half matters. Do not let an x64 copy
            # conceal a missing x86 builtin, or invent an uninstalled PE tree.
            if not (directory / name).is_file():
                missing.append({'dll': name, 'architecture_directory': directory.name, 'path': str(directory / name)})
    notes = []
    if builtin_names and not present:
        notes.append('The requested builtin layout could not be verified. This does not establish runtime corruption or WoW64 support.')
    elif builtin_names and not missing:
        notes.append('Reported Wine builtins are present in the checked layout. Verify the selected engine, program architecture and DLL loading; presence on disk does not prove successful loading.')
    return {'missing_builtins': missing, 'reported_builtins': builtin_names,
            'other_libraries': [name for name in names if name not in BUILTINS],
            'checked_directories': [str(path) for path in present], 'notes': notes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--log', required=True)
    parser.add_argument('--architecture', choices=['win32', 'win64'])
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    # Diagnose the same bounded log tail as the repair scanner.
    with open(args.log, 'rb') as stream:
        stream.seek(0, 2)
        stream.seek(max(0, stream.tell() - 262144))
        output = stream.read().decode('utf-8', errors='replace')
    result = diagnose(args.binary, output, args.architecture)
    if args.json:
        print(json.dumps(result))
    else:
        for item in result['missing_builtins']:
            print(f"[runtime] Wine builtin missing: {item['dll']} ({item['architecture_directory']}). Restore the matching Wine runtime; reinstalling the game or rebuilding its prefix will not replace this engine file.")
        for note in result['notes']:
            print('[runtime] ' + note)


if __name__ == '__main__':
    main()
