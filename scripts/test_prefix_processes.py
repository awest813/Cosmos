#!/usr/bin/env python3
import os
import signal
import tempfile
import unittest
from pathlib import Path
from lib.prefix_processes import ProcessRow, identity, owned_processes, stop


class PrefixProcessTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(); self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name).resolve()
        self.prefix = self.root / 'Game [One] with spaces'
        self.engine = self.root / 'runtime'
        (self.engine / 'bin').mkdir(parents=True)
        self.binary = self.engine / 'bin' / 'wine'
        self.binary.touch(); (self.engine / 'bin' / 'wineserver').touch()

    def row(self, pid, prefix=None, parent=1, executable=None, birth='123'):
        return ProcessRow(pid, parent, str(executable or self.binary), birth,
                          'wine Game.exe' + (f' WINEPREFIX={prefix} HOME=/fixture' if prefix is not None else ''))

    def test_exact_prefix_runtime_and_native_exclusions(self):
        rows = [self.row(10, self.prefix), self.row(11, str(self.prefix) + '-other'),
                self.row(12, self.prefix, executable=self.root / 'OtherWine/bin/wine'),
                self.row(13, self.prefix, executable=self.root / 'Steam.app/Steam'),
                self.row(14, self.prefix, birth='')]
        self.assertEqual([row.pid for row in owned_processes(rows, self.prefix, self.engine)], [10])

    def test_descendants_need_same_runtime_and_cannot_override_foreign_prefix(self):
        rows = [self.row(10, self.prefix), self.row(11, parent=10),
                self.row(12, self.root / 'other', parent=10),
                self.row(13, parent=10, executable=self.root / 'native-Steam')]
        self.assertEqual([row.pid for row in owned_processes(rows, self.prefix, self.engine)], [10, 11])

    def test_missing_prefix_is_not_inferred_from_an_argument(self):
        row = self.row(10)
        row = ProcessRow(row.pid, row.parent, row.executable, row.birth, f'wine {self.prefix}/drive_c/Game.exe')
        self.assertEqual(owned_processes([row], self.prefix, self.engine), [])

    def test_pid_reuse_never_receives_a_signal(self):
        row = self.row(10, self.prefix)
        signals = []
        count, left = stop(self.prefix, self.binary, rows_provider=lambda: [row],
                           identity_provider=lambda pid: (row.executable, 'new-birth'),
                           sender=lambda *args: signals.append(args), server_runner=lambda *args, **kw: None,
                           sleeper=lambda _: None)
        self.assertEqual((count, left), (1, 0)); self.assertEqual(signals, [])

    def test_bounded_server_and_term_escalation_are_prefix_scoped(self):
        row = self.row(10, self.prefix)
        live = {10: (row.executable, row.birth)}
        calls = []; servers = []
        def send(pid, sig):
            calls.append((pid, sig))
            if sig == signal.SIGTERM: live.pop(pid, None)
        def server(*args, **kw):
            servers.append(kw)
        self.assertEqual(stop(self.prefix, self.binary, rows_provider=lambda: [row], identity_provider=live.get,
                              sender=send, server_runner=server, sleeper=lambda _: None), (1, 0))
        self.assertEqual(calls, [(10, signal.SIGTERM)])
        self.assertEqual(servers[0]['env']['WINEPREFIX'], str(self.prefix))
        self.assertEqual(servers[0]['timeout'], 1.5)

    def test_kernel_identity_for_test_process_is_available(self):
        result = identity(os.getpid())
        self.assertIsNotNone(result)
        self.assertTrue(Path(result[0]).is_file()); self.assertTrue(result[1])


if __name__ == '__main__':
    unittest.main()
