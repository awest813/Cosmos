#!/usr/bin/env python3
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from lib.environment_clone import clone


class EnvironmentCloneTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(); self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name).resolve()
        self.source = self.root / 'original'
        self.prefix = self.source / 'prefix'
        (self.prefix / 'drive_c/Games').mkdir(parents=True)
        (self.prefix / 'dosdevices').mkdir()
        (self.source / 'bottle.conf').write_text('COSMOS_BACKEND="wined3d"\n')
        (self.prefix / 'system.reg').write_text('registry fixture')
        (self.prefix / 'dosdevices/z:').symlink_to('/')
        (self.prefix / 'dosdevices/c:').symlink_to('../drive_c')
        (self.source / 'install-game.conf').write_text(f'INSTALL_BOTTLE="original"\nINSTALL_FOLDER="{self.prefix}/drive_c/Games"\n')

    def copy(self, destination='copy', **kw):
        return clone(self.root, 'original', destination, stopper=lambda *args: (0, 0), idle_check=lambda *args: True, **kw)

    def test_complete_clone_keeps_source_and_preserves_links(self):
        before = (self.prefix / 'system.reg').read_bytes()
        copied = self.copy()
        self.assertEqual((copied / 'prefix/system.reg').read_bytes(), before)
        self.assertEqual((self.prefix / 'system.reg').read_bytes(), before)
        self.assertTrue((copied / 'prefix/dosdevices/z:').is_symlink())
        self.assertEqual(os.readlink(copied / 'prefix/dosdevices/z:'), '/')
        self.assertEqual(os.readlink(copied / 'prefix/dosdevices/c:'), '../drive_c')
        self.assertIn('INSTALL_BOTTLE="copy"', (copied / 'install-game.conf').read_text())
        self.assertIn(str(copied / 'prefix/drive_c/Games'), (copied / 'install-game.conf').read_text())

    def test_existing_destination_is_preserved(self):
        existing = self.root / 'copy'; existing.mkdir()
        (existing / 'keep').write_text('keep')
        with self.assertRaises(FileExistsError): self.copy()
        self.assertEqual((existing / 'keep').read_text(), 'keep')

    def test_failed_copy_never_publishes_or_modifies_source(self):
        def fail(*args): raise OSError('simulated disk failure')
        with self.assertRaises(shutil.Error): self.copy(copier=fail)
        self.assertFalse((self.root / 'copy').exists())
        self.assertFalse(list(self.root.glob('.clone-*')))
        self.assertEqual((self.prefix / 'system.reg').read_text(), 'registry fixture')

    def test_regular_copy_preserves_reparse_xattrs(self):
        stub = self.prefix / 'drive_c/Link?'; stub.mkdir()
        try: os.setxattr(stub, 'user.WINEREPARSE', b'fixture attribute')
        except OSError as error: self.skipTest(str(error))
        copied = self.copy(copier=shutil.copy2)
        self.assertEqual(os.getxattr(copied / 'prefix/drive_c/Link?', 'user.WINEREPARSE'), b'fixture attribute')

    def test_running_source_is_refused_before_copy(self):
        with self.assertRaises(ValueError):
            clone(self.root, 'original', 'copy', stopper=lambda *args: (1, 1), idle_check=lambda *args: False)
        self.assertFalse((self.root / 'copy').exists())

    def test_uninitialized_settings_can_be_cloned_without_initializing_source(self):
        shutil.rmtree(self.prefix)
        copied = self.copy()
        self.assertFalse(self.prefix.exists())
        self.assertTrue((copied / 'prefix').is_dir())
        self.assertFalse((copied / 'prefix/system.reg').exists())


if __name__ == '__main__': unittest.main()
