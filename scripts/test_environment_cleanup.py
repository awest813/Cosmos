#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from lib.environment_cleanup import cleanup


class EnvironmentCleanupTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(); self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name).resolve() / 'Bottles'; self.root.mkdir()
        self.bottle = self.root / 'game'
        self.prefix = self.bottle / 'prefix'
        (self.prefix / 'dosdevices').mkdir(parents=True)
        (self.prefix / 'system.reg').write_text('fixture registry')
        (self.bottle / 'bottle.conf').write_text('COSMOS_BACKEND="wined3d"\n')
        (self.bottle / 'logs').mkdir()
        (self.bottle / 'logs/launch.log').write_text('fixture log')
        self.external = self.root.parent / 'External'; self.external.mkdir()
        (self.external / 'save.dat').write_text('keep this save')
        (self.prefix / 'dosdevices/z:').symlink_to('/')
        (self.prefix / 'dosdevices/d:').symlink_to(self.external)
        (self.prefix / 'user-link').symlink_to(self.external)

    def remove(self, operation='reset', **kwargs):
        return cleanup(self.root, 'game', operation, stopper=lambda *args: (0, 0), idle_check=lambda *args: True, **kwargs)

    def test_reset_keeps_settings_logs_and_external_saves(self):
        self.remove()
        self.assertFalse(self.prefix.exists())
        self.assertEqual((self.bottle / 'logs/launch.log').read_text(), 'fixture log')
        self.assertTrue((self.bottle / 'bottle.conf').is_file())
        self.assertEqual((self.external / 'save.dat').read_text(), 'keep this save')

    def test_delete_never_follows_drive_or_user_links(self):
        self.remove('delete')
        self.assertFalse(self.bottle.exists())
        self.assertEqual((self.external / 'save.dat').read_text(), 'keep this save')
        self.assertFalse(list(self.root.glob('.cleanup-*')))

    def test_linked_prefix_and_linked_bottle_are_refused(self):
        import shutil
        shutil.rmtree(self.prefix)
        self.prefix.symlink_to(self.external)
        with self.assertRaisesRegex(ValueError, 'Linked'): self.remove('delete')
        self.assertTrue((self.bottle / 'bottle.conf').is_file())
        self.prefix.unlink()
        actual = self.root / 'actual'; self.bottle.rename(actual)
        self.bottle.symlink_to(actual)
        with self.assertRaisesRegex(ValueError, 'Linked'): self.remove('delete')
        self.assertTrue((actual / 'bottle.conf').is_file())

    def test_running_or_uncertain_environment_is_preserved(self):
        with self.assertRaisesRegex(ValueError, 'Wine is still running'):
            cleanup(self.root, 'game', 'delete', stopper=lambda *args: (1, 1), idle_check=lambda *args: False)
        self.assertTrue((self.prefix / 'system.reg').exists())
        self.assertFalse(list(self.root.glob('.cleanup-*')))

    def test_mount_boundary_is_refused_before_shutdown(self):
        with patch('lib.environment_cleanup.os.path.ismount', side_effect=lambda path: Path(path) == self.prefix):
            with self.assertRaisesRegex(ValueError, 'Unmount'):
                self.remove('delete', remover=lambda _: self.fail('Cleanup must not start'))
        self.assertTrue(self.prefix.is_dir())

    def test_failed_removal_reports_and_preserves_detached_files(self):
        def fail(path): raise PermissionError('fixture locked file')
        with self.assertRaisesRegex(OSError, 'Remaining files are preserved at') as caught:
            self.remove(remover=fail)
        leftovers = list(self.root.glob('.cleanup-*'))
        self.assertEqual(len(leftovers), 1)
        self.assertIn(str(leftovers[0]), str(caught.exception))
        self.assertEqual((leftovers[0] / 'system.reg').read_text(), 'fixture registry')
        self.assertTrue((self.bottle / 'bottle.conf').is_file())

    def test_changed_target_is_refused_without_removing_replacement(self):
        old = self.bottle / 'old-prefix'
        def stop_and_replace(*args):
            self.prefix.rename(old); self.prefix.mkdir()
            (self.prefix / 'keep').write_text('new prefix')
            return 0, 0
        with self.assertRaisesRegex(ValueError, 'changed during shutdown'):
            cleanup(self.root, 'game', 'reset', stopper=stop_and_replace, idle_check=lambda *args: True)
        self.assertEqual((self.prefix / 'keep').read_text(), 'new prefix')
        self.assertTrue((old / 'system.reg').exists())

    def test_missing_prefix_reset_is_idempotent(self):
        self.remove()
        self.assertIsNone(self.remove())
        self.assertTrue((self.bottle / 'bottle.conf').exists())

    def test_cli_requires_confirmation_and_uses_scoped_cleanup(self):
        root = Path(__file__).resolve().parent.parent
        environment = {**os.environ, 'COSMOS_BOTTLES_DIR': str(self.root), 'WINE_ROOT': str(self.root / 'no-engine')}
        refused = subprocess.run([str(root / 'bottle.command'), 'delete', 'game'], env={**environment, 'COSMOS_FORCE': '0'},
                                 input='', capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertTrue(self.prefix.is_dir())
        result = subprocess.run([str(root / 'bottle.command'), 'delete', 'game', '--force'], env=environment,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.bottle.exists())
        self.assertEqual((self.external / 'save.dat').read_text(), 'keep this save')


if __name__ == '__main__': unittest.main()
