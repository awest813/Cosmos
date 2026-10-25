#!/usr/bin/env python3
import hashlib
import io
import tempfile
import unittest
import urllib.error
from pathlib import Path
from lib.component_download import activate, download


class Response:
    def __init__(self, status, body, **headers):
        self.status, self.body, self.headers = status, io.BytesIO(body), headers
    def read(self, size): return self.body.read(size)
    def __enter__(self): return self
    def __exit__(self, *args): self.body.close()


class ComponentDownloadTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(); self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.data = b'abcdef'; self.sha = hashlib.sha256(self.data).hexdigest()
        self.calls = []

    def fetch(self, responses):
        def opener(request, **kwargs):
            self.calls.append(dict(request.header_items()))
            response = responses.pop(0)
            if isinstance(response, Exception): raise response
            return response
        return download('https://example.test/component', self.sha, self.root / 'cache', opener=opener, sleeper=lambda _: None)

    def interrupted(self): return Response(200, b'abc', **{'Content-Length': '6', 'ETag': '"one"'})
    def complete(self): return Response(200, self.data, **{'Content-Length': '6', 'ETag': '"two"'})

    def test_interrupted_download_resumes_with_if_range_and_verified_hash(self):
        archive = self.fetch([self.interrupted(), Response(206, b'def', **{'Content-Range': 'bytes 3-5/6', 'Content-Length': '3', 'ETag': '"one"'})])
        self.assertEqual(archive.read_bytes(), self.data)
        self.assertEqual(self.calls[1]['Range'], 'bytes=3-')
        self.assertEqual(self.calls[1]['If-range'], '"one"')
        self.assertFalse(list((self.root / 'cache').glob('*.partial')))

    def test_changed_etag_or_ignored_range_restarts_instead_of_appending(self):
        archive = self.fetch([self.interrupted(), self.complete()])
        self.assertEqual(archive.read_bytes(), self.data)

    def test_invalid_content_range_discards_partial_and_retries_full(self):
        archive = self.fetch([self.interrupted(), Response(206, b'def', **{'Content-Range': 'bytes 1-3/6', 'ETag': '"one"'}), self.complete()])
        self.assertEqual(archive.read_bytes(), self.data)
        self.assertNotIn('Range', self.calls[2])

    def test_416_resets_range_state(self):
        archive = self.fetch([self.interrupted(), urllib.error.HTTPError('https://example.test/component', 416, 'range', {}, None), self.complete()])
        self.assertEqual(archive.read_bytes(), self.data)
        self.assertNotIn('Range', self.calls[2])

    def test_wrong_checksum_never_publishes(self):
        with self.assertRaises(OSError):
            self.fetch([Response(200, b'bad') for _ in range(3)])
        self.assertFalse(list((self.root / 'cache').glob('*.archive')))

    def test_verified_cache_is_reused_without_a_request(self):
        archive = self.fetch([self.complete()])
        self.calls.clear()
        self.assertEqual(self.fetch([]), archive)
        self.assertFalse(self.calls)

    def test_failed_staging_keeps_active_installation(self):
        payload = self.root / 'payload'; payload.mkdir(); (payload / 'new').write_text('new')
        destination = self.root / 'active'; destination.mkdir(); (destination / 'old').write_text('old')
        def fail(*args, **kw): raise OSError('disk full')
        with self.assertRaises(OSError): activate(payload, destination, copier=fail)
        self.assertEqual((destination / 'old').read_text(), 'old')
        self.assertFalse((destination / 'new').exists())
        activate(payload, destination)
        self.assertEqual((destination / 'new').read_text(), 'new')
        self.assertEqual(list(self.root.glob('.active.previous-*'))[0].joinpath('old').read_text(), 'old')


if __name__ == '__main__': unittest.main()
