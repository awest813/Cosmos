"""Scoped reset/delete for named Wine environments; never follows drive links.

Extends Cosmos's Vermut-inspired ownership checks with Cosmos cleanup policy.
Only the requested tree is detached; incomplete removal retains a recovery path.
"""
import argparse
import os
import shutil
import stat
import subprocess
import sys
import uuid
from pathlib import Path
try:
    from .environment_clone import idle, publish_exclusively, valid_name
    from .prefix_processes import configured_binary, stop
except ImportError:
    from environment_clone import idle, publish_exclusively, valid_name
    from prefix_processes import configured_binary, stop


def check_tree(path, device):
    """Reject nested mounted folders; ordinary symlinks remain opaque entries."""
    for directory, directories, files in os.walk(path, followlinks=False):
        for entry in [Path(directory)] + [Path(directory) / name for name in directories + files]:
            info = entry.lstat()
            if stat.S_ISLNK(info.st_mode):
                continue
            if info.st_dev != device or os.path.ismount(entry):
                raise ValueError(f'Unmount this folder before removing the environment: {entry}')


def cleanup(root, name, operation, stopper=stop, idle_check=idle, remover=shutil.rmtree):
    if not valid_name(name) or operation not in {'reset', 'delete'}:
        raise ValueError('Choose a valid named environment and reset or delete')
    root = Path(root).resolve()
    bottle = root / name
    prefix = bottle / 'prefix'
    if bottle.is_symlink() or prefix.is_symlink():
        raise ValueError('Linked environments/prefixes cannot be reset or deleted. Remove the link explicitly instead.')
    if not bottle.is_dir() or not (bottle / 'bottle.conf').is_file():
        raise ValueError('A named environment with bottle.conf is required')
    target = prefix if operation == 'reset' else bottle
    if not os.path.lexists(target):
        return None
    if not target.is_dir():
        raise ValueError('The selected Windows environment is not a directory')
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError('This Python cannot perform protected environment cleanup; no files were removed')
    original = target.lstat()
    check_tree(target, root.stat().st_dev)
    binary = configured_binary(prefix)
    _, remaining = stopper(prefix, binary)
    if remaining or not idle_check(prefix, binary):
        raise ValueError('Wine is still running or ownership is uncertain. Save and close it before retrying.')
    current = target.lstat()
    if (current.st_dev, current.st_ino) != (original.st_dev, original.st_ino) or target.is_symlink():
        raise ValueError('The environment changed during shutdown; no files were removed')
    detached = root / ('.cleanup-' + name + '-' + uuid.uuid4().hex)
    publish_exclusively(target, detached)
    try:
        moved = detached.lstat()
        if (moved.st_dev, moved.st_ino) != (original.st_dev, original.st_ino):
            raise ValueError('The environment changed before cleanup')
        check_tree(detached, original.st_dev)
        remover(detached)
    except (OSError, ValueError, shutil.Error) as error:
        raise OSError(f'Cleanup stopped: {error}. Remaining files are preserved at {detached}; inspect them before manual recovery or removal.') from error
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['reset', 'delete'])
    parser.add_argument('name')
    parser.add_argument('--bottles-root', required=True)
    args = parser.parse_args()
    try:
        print('Stopping the selected environment before removing its Windows files…', flush=True)
        result = cleanup(args.bottles_root, args.name, args.operation)
        if result is None:
            print('There is no Windows prefix to reset.')
        elif args.operation == 'reset':
            print('Windows prefix reset. Settings/logs were kept. Ports still reference this environment; reinstall its games before launching them.')
        else:
            print('Environment deleted. External linked folders and port definitions were kept. Edit or remove ports that referenced this environment.')
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Error: Environment cleanup failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
