"""Read-only host/Windows path resolution for one Wine prefix."""
import argparse
import json
import os
import re
import sys
import struct
import ctypes
from pathlib import Path

# Reparse buffer layout/read-only stub following adapted from Highball's
# WineReparsePoint.swift (GPL-3.0), by the Highball contributors.
# https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/WineReparsePoint.swift
# Cosmos additions: bounded decoding, cycle detection and actual drive mappings.
def decode_reparse(data):
    if len(data) < 16 or len(data) > 16384:
        raise ValueError('Malformed Wine junction buffer')
    tag, length = struct.unpack_from('<IH', data)
    end = 8 + length
    if end > len(data) or end < 16:
        raise ValueError('Truncated Wine junction buffer')
    offset, size = struct.unpack_from('<HH', data, 8)
    if tag == 0xA000000C:
        if end < 20:
            raise ValueError('Truncated Wine symbolic link')
        flags = struct.unpack_from('<I', data, 16)[0]
        if flags & ~1:
            raise ValueError('Unsupported Wine symbolic link flags')
        base, relative = 20, bool(flags & 1)
    elif tag == 0xA0000003:
        base, relative = 16, False
    else:
        raise ValueError('Unsupported Wine reparse tag')
    if offset % 2 or size < 2 or size % 2 or base + offset + size > end:
        raise ValueError('Invalid Wine junction target bounds')
    try:
        target = data[base + offset:base + offset + size].decode('utf-16-le')
    except UnicodeError as error:
        raise ValueError('Invalid Wine junction target text') from error
    if '\0' in target:
        raise ValueError('Invalid null in Wine junction target')
    return target, relative


def read_attribute(path, name):
    if sys.platform != 'darwin':
        return os.getxattr(path, name, follow_symlinks=False)
    # Python's os xattr bindings are Linux-only. Darwin uses a six-argument
    # getxattr and XATTR_NOFOLLOW; never follow a Mac symlink to read its target.
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    reader = library.getxattr
    reader.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    reader.restype = ctypes.c_ssize_t
    arguments = (os.fsencode(path), os.fsencode(name))
    size = reader(*arguments, None, 0, 0, 1)
    if size < 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(path))
    if size > 16384:
        raise ValueError('Wine junction attribute exceeds the supported size')
    buffer = ctypes.create_string_buffer(size)
    count = reader(*arguments, buffer, size, 0, 1)
    if count < 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(path))
    return buffer.raw[:count]


def read_reparse(path):
    try:
        data = read_attribute(path, 'user.WINEREPARSE')
    except OSError as error:
        import errno
        if error.errno in (errno.ENOENT, errno.ENOTDIR, getattr(errno, 'ENODATA', -1),
                           getattr(errno, 'ENOATTR', -1), errno.ENOTSUP):
            return None
        raise
    return decode_reparse(data)


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


def case_component(current, part, insensitive=True):
    """Prefer exact names; resolve Windows case-insensitive names unambiguously."""
    exact = current / part
    if not os.path.lexists(exact) and current.is_dir() and insensitive:
        matches = [entry for entry in current.iterdir() if entry.name.casefold() == part.casefold()]
        if len(matches) > 1:
            raise ValueError(f'Ambiguous Windows filename: {exact}')
        if matches:
            exact = matches[0]
    return exact


def junction_target(prefix, parent, decoded):
    target, relative = decoded
    for namespace in ('\\??\\', '\\\\?\\'):
        if target.startswith(namespace):
            target = target[len(namespace):]
            break
    if not relative:
        if not re.match(r'^[a-zA-Z]:[\\/]', target):
            raise ValueError('Unsupported absolute Wine junction target')
        return drive_root(prefix, target[0]).joinpath(*relative_parts(target[3:].replace('\\', '/')))
    parent = canonical(parent)
    if target.startswith(('\\', '/')) or re.match(r'^[a-zA-Z]:', target):
        raise ValueError('Invalid relative Wine junction target')
    roots = sorted(mappings(prefix).values(), key=lambda root: -len(str(root)))
    for root in roots:
        try:
            before = parent.relative_to(root)
        except ValueError:
            continue
        parts = relative_parts(str(before) + '/' + target.replace('\\', '/'))
        return root.joinpath(*parts)
    raise ValueError('Relative Wine junction is outside mapped drives')


def follow_path(prefix, path, insensitive=True):
    path = Path(os.path.abspath(path))
    seen = set()
    for _ in range(33):
        current = Path(path.anchor)
        parts = path.parts[1:]
        for index, part in enumerate(parts):
            direct = case_component(current, part, insensitive)
            decoded = read_reparse(direct)
            stub = direct
            if decoded is None and not os.path.lexists(direct):
                stub = case_component(current, part + '?', insensitive)
                decoded = read_reparse(stub)
            if decoded is not None:
                state = (str(stub), parts[index + 1:])
                if state in seen:
                    raise ValueError('Cyclic Wine junction')
                seen.add(state)
                path = junction_target(prefix, current, decoded).joinpath(*parts[index + 1:])
                break
            current = direct
        else:
            return current
    raise ValueError('Wine junction nesting exceeds 32 links')


def host_path(prefix, text):
    prefix = Path(os.path.abspath(prefix))
    if not text or '\n' in text or '\r' in text:
        raise ValueError('A single-line path is required')
    if re.match(r'^[a-zA-Z]:[\\/]', text):
        return follow_path(prefix, drive_root(prefix, text[0]).joinpath(*relative_parts(text[3:].replace('\\', '/'))))
    if re.match(r'^[a-zA-Z]:', text) or text.startswith('\\'):
        raise ValueError('Use an absolute Windows drive path, such as C:\\Games\\Game.exe')
    if text.startswith('/'):
        return follow_path(prefix, Path(os.path.abspath(text)), insensitive=False)
    if text.startswith('drive_c/'):
        parts = relative_parts(text[len('drive_c/'):])
        return follow_path(prefix, (prefix / 'drive_c').joinpath(*parts))
    return follow_path(prefix, prefix.joinpath(*relative_parts(text)))


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
