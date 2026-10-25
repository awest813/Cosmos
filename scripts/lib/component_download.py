"""Verified resumable component downloads and staged runtime activation.

Range/ETag decision model informed by Highball DownloadResume (GPL-3.0),
Highball contributors, revision 1512223fff145eae3b4c9fb588edf86758bc756b.
https://github.com/gauthierpiarrette/highball/blob/1512223fff145eae3b4c9fb588edf86758bc756b/Sources/HighballKit/DownloadResume.swift
"""
import argparse
import fcntl
import hashlib
import http.client
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()


def download(url, sha256, cache, opener=urllib.request.urlopen, attempts=3, sleeper=time.sleep):
    if not re.fullmatch(r'[a-fA-F0-9]{64}', sha256 or ''):
        raise ValueError('A trusted SHA-256 pin is required before downloading a component')
    if not url.startswith('https://'):
        raise ValueError('Component downloads require HTTPS')
    sha256 = sha256.lower()
    cache = Path(cache); cache.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256((url + '\0' + sha256).encode()).hexdigest()
    archive, partial, metadata = [cache / (key + suffix) for suffix in ['.archive', '.partial', '.json']]
    with open(cache / (key + '.lock'), 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if archive.is_file() and digest(archive) == sha256: return archive
        archive.unlink(missing_ok=True)
        error = None
        for attempt in range(attempts):
            try:
                try: saved = json.loads(metadata.read_text())
                except (OSError, ValueError): saved = {}
                etag = saved.get('etag', '')
                have = partial.stat().st_size if partial.is_file() and etag and not etag.startswith('W/') else 0
                headers = {'Accept-Encoding': 'identity'}
                if have: headers.update({'Range': f'bytes={have}-', 'If-Range': etag})
                request = urllib.request.Request(url, headers=headers)
                try:
                    response = opener(request, timeout=30)
                except urllib.error.HTTPError as failure:
                    if failure.code == 416:
                        partial.unlink(missing_ok=True); metadata.unlink(missing_ok=True)
                    raise
                with response:
                    status = response.status
                    append = False
                    expected = None
                    if status == 206:
                        match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.headers.get('Content-Range', ''))
                        if not have or not match or int(match[1]) != have or int(match[2]) < have or int(match[3]) <= int(match[2]):
                            raise ValueError('Server returned an invalid component byte range')
                        if response.headers.get('ETag', etag) != etag:
                            raise ValueError('Component changed during a resumed download')
                        expected = int(match[3]); append = True
                        length = response.headers.get('Content-Length')
                        if length is not None and int(length) != int(match[2]) - have + 1:
                            raise ValueError('Component range length is inconsistent')
                    elif status == 200:
                        have = 0
                        if response.headers.get('Content-Length') is not None:
                            expected = int(response.headers['Content-Length'])
                    else:
                        raise ValueError(f'Unexpected component HTTP status {status}')
                    metadata.write_text(json.dumps({'etag': response.headers.get('ETag', '')}))
                    with open(partial, 'ab' if append else 'wb') as stream:
                        while True:
                            chunk = response.read(1024 * 1024)
                            if not chunk: break
                            stream.write(chunk)
                    if expected is not None and partial.stat().st_size != expected:
                        raise OSError('Component download was interrupted; the partial file was kept for retry')
                    if digest(partial) != sha256:
                        raise ValueError('Component SHA-256 verification failed')
                os.replace(partial, archive)
                metadata.unlink(missing_ok=True)
                return archive
            except (OSError, ValueError, http.client.HTTPException) as failure:
                error = failure
                if isinstance(failure, ValueError):
                    partial.unlink(missing_ok=True); metadata.unlink(missing_ok=True)
                if attempt + 1 < attempts: sleeper(min(1, attempt + 0.25))
        raise OSError(f'Component download failed after {attempts} attempts: {error}')


def activate(payload, destination, copier=shutil.copytree):
    payload, destination = Path(payload), Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.component-', dir=destination.parent))
    previous = destination.parent / ('.' + destination.name + '.previous-' + uuid.uuid4().hex)
    moved = False
    try:
        copier(payload, stage, symlinks=True, dirs_exist_ok=True)
        if os.path.lexists(destination):
            os.rename(destination, previous); moved = True
        try: os.rename(stage, destination)
        except OSError:
            if moved: os.rename(previous, destination)
            raise
        # Keep the previous installation as a recovery copy. Never merge a
        # partial extraction into the active engine or erase its predecessor.
        return destination
    finally:
        if stage.exists(): shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    fetch = sub.add_parser('fetch'); fetch.add_argument('--url', required=True); fetch.add_argument('--sha256', required=True); fetch.add_argument('--cache', required=True)
    install = sub.add_parser('activate'); install.add_argument('payload'); install.add_argument('destination')
    args = parser.parse_args()
    try:
        result = download(args.url, args.sha256, args.cache) if args.operation == 'fetch' else activate(args.payload, args.destination)
        print(result)
        return 0
    except (OSError, ValueError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
