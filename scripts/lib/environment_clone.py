"""Clone a stopped named environment without following drive links.

Complete-prefix scope follows Soju setup-bottle.sh (GPL-3.0, BCD1210/Soju
contributors, 43ed224336cdffdba9dc4b47aa858a5273eb0838). Cosmos implementation
adds non-following metadata copies, staged publication and metadata rebasing.
"""
import argparse
import ctypes
import errno
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
try:
    from .prefix_processes import configured_binary, owned_processes, snapshot, stop
except ImportError:
    from prefix_processes import configured_binary, owned_processes, snapshot, stop


def valid_name(name):
    return bool(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name)) and '..' not in name


def idle(prefix, binary):
    rows = snapshot()
    if owned_processes(rows, prefix, Path(binary).resolve().parent.parent):
        return False
    # A Wine executable explicitly naming this prefix, even from a different
    # runtime, is a reason to refuse a copy, not permission to stop that runtime.
    marker = str(Path(prefix).resolve())
    runtime = str(Path(binary).resolve().parent.parent)
    for row in rows:
        if Path(row.executable).name in {'wine', 'wine64', 'wine-preloader', 'wine64-preloader', 'wineserver', 'wineloader'}:
            match = re.search(r'(?:^|\s)WINEPREFIX=(.*?)(?=\s[A-Za-z_][A-Za-z0-9_]*=|$)', row.command)
            if match and os.path.realpath(match[1].strip('"\'')) == marker:
                return False
            if not match and os.path.realpath(row.executable).startswith(runtime + os.sep):
                return False
    return True


def copy_file(source, destination):
    if sys.platform == 'darwin':
        library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        if library.clonefile(os.fsencode(source), os.fsencode(destination), 0) == 0:
            return destination
        copy_metadata(source, destination, include_data=True)
        return destination
    return shutil.copy2(source, destination, follow_symlinks=False)


def copy_metadata(source, destination, include_data=False):
    if sys.platform != 'darwin':
        return
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    copy = library.copyfile
    copy.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_uint32]
    # COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR, optionally COPYFILE_DATA.
    if copy(os.fsencode(source), os.fsencode(destination), None, 15 if include_data else 7):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(source))


def publish_exclusively(source, destination):
    library = ctypes.CDLL(None, use_errno=True)
    if sys.platform == 'darwin':
        result = library.renamex_np(os.fsencode(source), os.fsencode(destination), 4)  # RENAME_EXCL
    elif hasattr(library, 'renameat2'):
        result = library.renameat2(-100, os.fsencode(source), -100, os.fsencode(destination), 1)
    else:
        raise OSError('Exclusive environment publication is unavailable on this platform')
    if result:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


def clone(root, source_name, destination_name, stopper=stop, idle_check=idle, copier=copy_file):
    if not valid_name(source_name) or not valid_name(destination_name):
        raise ValueError('Use valid environment names without spaces, slashes or ..')
    root = Path(root).resolve()
    source, destination = root / source_name, root / destination_name
    if not (source / 'bottle.conf').is_file():
        raise ValueError('Source environment settings are required')
    if os.path.lexists(source / 'prefix') and not (source / 'prefix').is_dir():
        raise ValueError('Source Windows prefix is not a directory')
    if source.is_symlink() or (source / 'prefix').is_symlink():
        raise ValueError('A linked source prefix cannot be cloned as independent Windows data')
    if os.path.lexists(destination):
        raise FileExistsError('Destination environment already exists; choose a new name')
    binary = configured_binary(source / 'prefix')
    _, remaining = stopper(source / 'prefix', binary)
    if remaining or not idle_check(source / 'prefix', binary):
        raise ValueError('The source environment is still running or its idle state could not be established')
    stage = Path(tempfile.mkdtemp(prefix='.clone-', dir=root))
    try:
        shutil.copytree(source, stage, symlinks=True, copy_function=copier, dirs_exist_ok=True)
        # shutil.copystat does not copy Darwin xattrs. Include directory stubs
        # as well as regular files, without visiting linked external folders.
        if sys.platform == 'darwin':
            for directory, directories, files in os.walk(stage, followlinks=False):
                for path in [Path(directory)] + [Path(directory) / name for name in files]:
                    if not path.is_symlink():
                        copy_metadata(source / path.relative_to(stage), path)
        (stage / 'prefix').mkdir(exist_ok=True)
        old_prefix = str(source / 'prefix')
        new_prefix = str(destination / 'prefix')
        # Never recurse through Windows drive/user links. Rebase only absolute
        # links into the source prefix; links to external Mac folders stay links.
        for directory, directories, files in os.walk(stage, followlinks=False):
            for name in directories + files:
                path = Path(directory) / name
                if not path.is_symlink():
                    continue
                target = os.readlink(path)
                resolved = os.path.realpath(target) if target.startswith('/') else target
                if resolved == old_prefix or resolved.startswith(old_prefix + '/'):
                    path.unlink()
                    path.symlink_to(new_prefix + resolved[len(old_prefix):])
        for record in stage.glob('install-*.conf'):
            lines = []
            for line in record.read_text().splitlines():
                if line.startswith('INSTALL_BOTTLE='):
                    line = f'INSTALL_BOTTLE="{destination_name}"'
                elif line.startswith(('INSTALL_FOLDER=', 'INSTALLER_PATH=')):
                    key, raw = line.split('=', 1)
                    value = raw.strip('"')
                    if value == old_prefix or value.startswith(old_prefix + '/'):
                        line = f'{key}="{new_prefix + value[len(old_prefix):]}"'
                lines.append(line)
            record.write_text('\n'.join(lines) + '\n')
        publish_exclusively(stage, destination)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--name', required=True)
    parser.add_argument('--bottles-root', required=True)
    args = parser.parse_args()
    try:
        print('Stopping only the selected environment and copying its Windows state…', flush=True)
        destination = clone(args.bottles_root, args.source, args.name)
        print(f'Cloned environment: {destination}. External drive folders remain linked; create a port using the new environment to launch its games.')
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Error: Environment clone failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
