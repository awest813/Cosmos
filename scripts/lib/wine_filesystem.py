"""Read-only host/Windows path resolution for one Wine prefix."""
import argparse
import json
import os
import re
import sys
from pathlib import Path


def canonical(path):
    return Path(os.path.realpath(path))


def drive_root(prefix, letter):
    mapping = prefix / 'dosdevices' / (letter.lower() + ':')
    if os.path.lexists(mapping):
        if not mapping.is_symlink() or not mapping.is_dir():
            raise ValueError(f'Drive {letter.upper()}: has a missing or invalid mapping: {mapping}')
        return canonical(mapping)
    if letter.lower() == 'c':
        return canonical(prefix / 'drive_c')
    if letter.lower() == 'z' and not (prefix / 'system.reg').is_file():
        return Path('/')  # Wine's default for a prefix not initialized yet.
    raise ValueError(f'Drive {letter.upper()}: is not mapped in this environment')


def relative_parts(text):
    parts = []
    for part in text.split('/'):
        if part in ('', '.'):
            continue
        if part == '..':
            if not parts:
                raise ValueError('Path escapes its Windows drive or environment root')
            parts.pop()
        else:
            parts.append(part)
    return parts


def case_path(root, parts):
    """Prefer exact names; resolve Windows case-insensitive names unambiguously."""
    current = root
    for part in parts:
        exact = current / part
        if not os.path.lexists(exact) and current.is_dir():
            matches = [entry for entry in current.iterdir() if entry.name.casefold() == part.casefold()]
            if len(matches) > 1:
                raise ValueError(f'Ambiguous Windows filename: {exact}')
            if matches:
                exact = matches[0]
        current = exact
    return current


def host_path(prefix, text):
    prefix = Path(os.path.abspath(prefix))
    if not text or '\n' in text or '\r' in text:
        raise ValueError('A single-line path is required')
    if re.match(r'^[a-zA-Z]:[\\/]', text):
        return case_path(drive_root(prefix, text[0]), relative_parts(text[3:].replace('\\', '/')))
    if re.match(r'^[a-zA-Z]:', text) or text.startswith('\\'):
        raise ValueError('Use an absolute Windows drive path, such as C:\\Games\\Game.exe')
    if text.startswith('/'):
        return Path(os.path.abspath(text))
    if text.startswith('drive_c/'):
        return case_path(prefix / 'drive_c', relative_parts(text[len('drive_c/'):]))
    return case_path(prefix, relative_parts(text))


def mappings(prefix):
    prefix = Path(prefix)
    roots = {}
    for letter in ['c'] + [chr(i) for i in range(ord('a'), ord('z') + 1) if i != ord('c')]:
        try:
            root = drive_root(prefix, letter)
        except ValueError:
            continue
        roots[letter] = root
    return roots


def windows_path(prefix, text):
    host = canonical(host_path(prefix, text))
    choices = []
    for letter, root in mappings(prefix).items():
        try:
            relative = host.relative_to(root)
        except ValueError:
            continue
        choices.append((len(str(root)), letter == 'c', letter, relative))
    if not choices:
        raise ValueError(f'No Windows drive maps to {host}. Configure a drive in Wine before installing there.')
    _, _, letter, relative = min(choices, key=lambda item: (-item[0], not item[1], item[2]))
    suffix = '' if str(relative) == '.' else str(relative).replace('/', '\\')
    return letter.upper() + ':\\' + suffix


def inspect(prefix):
    prefix = Path(os.path.abspath(prefix))
    try:
        c_root = drive_root(prefix, 'c')
    except ValueError:
        c_root = None
    locations = {
        'drive_c_storage': str(prefix / 'drive_c'),
        'drive_mappings': str(prefix / 'dosdevices'),
    }
    for name, relative in {
        'windows_drive': '', 'games': 'Games', 'users': 'users',
        'program_files': 'Program Files', 'program_files_x86': 'Program Files (x86)',
        'system32': 'windows/system32', 'syswow64': 'windows/syswow64',
    }.items():
        locations[name] = str(c_root / relative) if c_root is not None else None
    errors = {}
    directory = prefix / 'dosdevices'
    if directory.is_dir():
        for entry in directory.iterdir():
            if re.fullmatch(r'[a-z]:', entry.name):
                try:
                    drive_root(prefix, entry.name[0])
                except ValueError as error:
                    errors[entry.name.upper()] = str(error)
    return {
        'prefix': str(prefix),
        'initialized': (prefix / 'system.reg').is_file(),
        'default_mappings_assumed': not (prefix / 'system.reg').is_file(),
        'locations': locations,
        'drives': {letter.upper() + ':': str(root) for letter, root in mappings(prefix).items()},
        'drive_errors': errors,
        'note': 'File layout only; no Wine process was started and no game compatibility was tested.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['host', 'windows', 'inspect'])
    parser.add_argument('prefix')
    parser.add_argument('path', nargs='?')
    args = parser.parse_args()
    try:
        if args.operation == 'inspect':
            print(json.dumps(inspect(args.prefix), indent=2))
        elif args.path is None:
            parser.error('path is required')
        elif args.operation == 'host':
            print(host_path(args.prefix, args.path))
        else:
            print(windows_path(args.prefix, args.path))
    except (OSError, ValueError) as error:
        print(f'Filesystem: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
