"""Bounded Wine process control scoped to a prefix and runtime.

Ownership/escalation design adapted from Vermut PrefixProcessTerminator (MIT),
revision 3ad9649ee0ff88812052af3672992dfa354c1892, Vermut Contributors (2026).
https://github.com/Contessafry/Vermut/blob/3ad9649ee0ff88812052af3672992dfa354c1892/Sources/CaskLauncherCore/PrefixProcessTerminator.swift

MIT License: Copyright (c) 2026 Vermut Contributors.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
import argparse
import ctypes
import os
import re
import signal
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProcessRow:
    pid: int
    parent: int
    executable: str
    birth: str
    command: str


def identity(pid):
    """Kernel executable + process birth identity; unavailable means no signal."""
    try:
        if sys.platform == 'darwin':
            library = ctypes.CDLL('/usr/lib/libproc.dylib')
            path = ctypes.create_string_buffer(4096)
            if library.proc_pidpath(pid, path, len(path)) <= 0:
                return None
            info = ctypes.create_string_buffer(136)
            library.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
            if library.proc_pidinfo(pid, 3, 0, info, len(info)) != 136:
                return None
            if struct.unpack_from('=I', info.raw, 12)[0] != pid or struct.unpack_from('=I', info.raw, 4)[0] == 5:
                return None
            birth = struct.unpack_from('=QQ', info.raw, 120)
            return os.path.realpath(os.fsdecode(path.value)), f'{birth[0]}.{birth[1]}'
        stat = Path(f'/proc/{pid}/stat').read_text()
        fields = stat[stat.rfind(')') + 2:].split()
        if fields[0] == 'Z':
            return None
        return os.path.realpath(f'/proc/{pid}/exe'), fields[19]
    except (OSError, ValueError, IndexError):
        return None


def snapshot():
    arguments = ['/bin/ps', '-axEww' if sys.platform == 'darwin' else 'axeww', '-o', 'pid=,ppid=,command=']
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=2, check=True)
    rows = []
    for line in result.stdout.splitlines():
        pieces = line.split(None, 2)
        if len(pieces) != 3 or not pieces[0].isdigit() or not pieces[1].isdigit():
            continue
        pid = int(pieces[0])
        found = identity(pid)
        if found:
            rows.append(ProcessRow(pid, int(pieces[1]), found[0], found[1], pieces[2]))
    # Raw process environments are never printed, saved or included in reports.
    return rows


def owned_processes(rows, prefix, runtime):
    prefix, runtime = os.path.realpath(prefix), os.path.realpath(runtime)
    allowed = {'wine', 'wine64', 'wine-preloader', 'wine64-preloader', 'wineserver', 'wineloader'}
    def is_wine(row):
        executable = os.path.realpath(row.executable)
        return executable.startswith(runtime + os.sep) and Path(executable).name in allowed
    selected = set()
    declared = {}
    for row in rows:
        match = re.search(r'(?:^|\s)WINEPREFIX=(.*?)(?=\s[A-Za-z_][A-Za-z0-9_]*=|$)', row.command)
        value = match[1].strip('"\'') if match else None
        declared[row.pid] = os.path.realpath(value) if value and value.startswith('/') else ('' if match else None)
    for row in rows:
        if row.pid <= 1 or not row.birth or not is_wine(row):
            continue
        if declared[row.pid] == prefix:
            selected.add(row.pid)
    while True:
        children = {row.pid for row in rows if row.pid > 1 and row.birth and row.parent in selected and is_wine(row) and declared[row.pid] in (None, prefix)}
        if children <= selected:
            break
        selected |= children
    return [row for row in rows if row.pid in selected]


def configured_binary(prefix):
    if os.environ.get('WINE_BIN'):
        return Path(os.environ['WINE_BIN'])
    configuration = Path(prefix).parent / 'bottle.conf'
    if not configuration.is_file():
        configuration = Path(os.environ.get('COSMOS_SUPPORT_DIR', str(Path.home() / 'Library/Application Support/Cosmos'))) / 'steam.conf'
    values = {}
    if configuration.is_file():
        for line in configuration.read_text().splitlines():
            if '=' in line:
                key, value = line.split('=', 1); values[key.strip()] = value.strip().strip('"')
    version = os.environ.get('WINE_VERSION') or values.get('WINE_VERSION') or '11.8'
    root = Path(os.environ.get('WINE_ROOT', str(Path.home() / f'wine-{version}')))
    return root / 'Wine Devel.app/Contents/Resources/wine/bin/wine'


def stop(prefix, binary, rows_provider=snapshot, identity_provider=identity, sender=os.kill, server_runner=subprocess.run, sleeper=time.sleep):
    prefix = Path(prefix).resolve()
    if prefix in (Path('/'), Path.home().resolve()):
        raise ValueError('Refusing an environment root equal to / or the home folder')
    binary = Path(binary).resolve()
    runtime = binary.parent.parent
    selected = owned_processes(rows_provider(), prefix, runtime)
    if not selected:
        return 0, 0
    server = binary.parent / 'wineserver'
    if server.is_file():
        try:
            server_runner([str(server), '-k'], env={**os.environ, 'WINEPREFIX': str(prefix)},
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.5, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass
    def live(row):
        return identity_provider(row.pid) == (os.path.realpath(row.executable), row.birth)
    # Revalidate the executable and birth token before each signal: a reused PID
    # is never permission to target the new process.
    for sig, grace in [(signal.SIGTERM, 0.75), (signal.SIGKILL, 0.25)]:
        for row in selected:
            if live(row):
                try:
                    sender(row.pid, sig)
                except ProcessLookupError:
                    pass
        sleeper(grace)
    return len(selected), sum(live(row) for row in selected)


def main():
    parser = argparse.ArgumentParser(description='Stop only positively identified Wine processes for one prefix.')
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--binary')
    parser.add_argument('--check', action='store_true', help='Count matching processes without sending signals')
    args = parser.parse_args()
    try:
        binary = Path(args.binary) if args.binary else configured_binary(args.prefix)
        if args.check:
            print(len(owned_processes(snapshot(), args.prefix, binary.resolve().parent.parent)))
            return 0
        count, remaining = stop(args.prefix, binary)
        print(f'Selected environment: {count} Wine processes identified; {remaining} remain after bounded shutdown.')
        return 1 if remaining else 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Process control: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
