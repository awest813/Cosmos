#!/usr/bin/env python3
"""Filesystem contract tests; no Wine or user data involved."""
import tempfile
import unittest
from pathlib import Path
from lib.wine_filesystem import host_path, windows_path, inspect


class WineFilesystemTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name).resolve()
        self.prefix = self.root / 'prefix'
        (self.prefix / 'drive_c' / 'Games' / 'SimCity').mkdir(parents=True)
        self.game = self.prefix / 'drive_c' / 'Games' / 'SimCity' / 'SC3U.exe'
        self.game.write_bytes(b'fixture')

    def initialized(self):
        (self.prefix / 'system.reg').write_text('WINE REGISTRY Version 2\n#arch=win64\n')
        (self.prefix / 'dosdevices').mkdir(exist_ok=True)

    def test_c_paths_and_prefix_relative_paths_agree(self):
        for path in [r'C:\Games\SimCity\SC3U.exe', 'C:/Games/SimCity/SC3U.exe', 'drive_c/Games/SimCity/SC3U.exe']:
            self.assertEqual(host_path(self.prefix, path), self.game)
        self.assertEqual(windows_path(self.prefix, str(self.game)), r'C:\Games\SimCity\SC3U.exe')
        self.assertEqual(windows_path(self.prefix, str(self.prefix / 'drive_c')), 'C:\\')

    def test_case_insensitive_windows_lookup_on_sensitive_volume(self):
        self.assertEqual(host_path(self.prefix, r'c:\games\simcity\sc3u.EXE'), self.game)

    def test_mapped_external_drive_round_trip(self):
        self.initialized()
        external = self.root / 'External Games'; external.mkdir()
        (external / 'Game.exe').write_bytes(b'fixture')
        (self.prefix / 'dosdevices' / 'd:').symlink_to(external, target_is_directory=True)
        self.assertEqual(host_path(self.prefix, r'D:\Game.exe'), external / 'Game.exe')
        self.assertEqual(windows_path(self.prefix, str(external / 'Game.exe')), r'D:\Game.exe')

    def test_remapped_z_does_not_forge_a_host_root_path(self):
        self.initialized()
        external = self.root / 'External Games'; external.mkdir()
        (self.prefix / 'dosdevices' / 'z:').symlink_to(external, target_is_directory=True)
        self.assertEqual(windows_path(self.prefix, str(external / 'Game Folder')), r'Z:\Game Folder')
        with self.assertRaises(ValueError):
            windows_path(self.prefix, str(self.root / 'Unmapped'))

    def test_initialized_environment_needs_a_real_mapping(self):
        self.initialized()
        with self.assertRaises(ValueError):
            windows_path(self.prefix, str(self.root / 'Outside'))
        with self.assertRaises(ValueError):
            host_path(self.prefix, r'Z:\Outside')

    def test_fresh_environment_reports_assumed_defaults_without_creation(self):
        prefix = self.root / 'Not Created'
        report = inspect(prefix)
        self.assertFalse(prefix.exists())
        self.assertTrue(report['default_mappings_assumed'])
        self.assertEqual(report['drives']['Z:'], '/')

    def test_path_traversal_and_drive_relative_paths_are_rejected(self):
        for text in ['drive_c/../../outside', r'C:\..\outside', 'C:relative.exe', r'\\server\share\game.exe', '../outside']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                host_path(self.prefix, text)

    def test_symlinked_c_drive_and_most_specific_mapping(self):
        self.initialized()
        external = self.root / 'Windows Drive'; external.mkdir()
        (self.prefix / 'dosdevices' / 'c:').symlink_to(external, target_is_directory=True)
        (self.prefix / 'dosdevices' / 'z:').symlink_to('/', target_is_directory=True)
        self.assertEqual(host_path(self.prefix, r'C:\Game.exe'), external / 'Game.exe')
        self.assertEqual(windows_path(self.prefix, str(external / 'Game.exe')), r'C:\Game.exe')
        self.assertEqual(inspect(self.prefix)['locations']['games'], str(external / 'Games'))

    def test_broken_drive_mapping_is_not_silently_replaced(self):
        self.initialized()
        (self.prefix / 'dosdevices' / 'c:').symlink_to(self.root / 'Missing')
        with self.assertRaises(ValueError):
            host_path(self.prefix, r'C:\Game.exe')
        self.assertIn('C:', inspect(self.prefix)['drive_errors'])
        self.assertIsNone(inspect(self.prefix)['locations']['windows_drive'])

    def test_same_windows_path_stays_in_selected_environment(self):
        other = self.root / 'other'
        (other / 'drive_c').mkdir(parents=True)
        self.assertEqual(host_path(other, r'C:\Games\Game.exe'), other / 'drive_c' / 'Games' / 'Game.exe')
        self.assertNotEqual(host_path(other, r'C:\Games\Game.exe'), host_path(self.prefix, r'C:\Games\Game.exe'))


if __name__ == '__main__':
    unittest.main()
