#!/usr/bin/env python3
import os
import struct
import tempfile
import unittest
from xattr_fixtures import read_attribute, set_attribute
from pathlib import Path
from lib.wine_filesystem import decode_reparse, host_path
from lib.runtime_integrity import diagnose


def reparse(target, relative=False, junction=True):
    text = target.encode('utf-16-le')
    body = struct.pack('<HHHH', 0, len(text), 0, 0)
    if not junction:
        body += struct.pack('<I', int(relative))
    body += text
    return struct.pack('<IHH', 0xA0000003 if junction else 0xA000000C, len(body), 0) + body


class AuditDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name).resolve()
        self.prefix = self.root / 'prefix'
        self.drive = self.prefix / 'drive_c'
        self.drive.mkdir(parents=True)

    def stub(self, name, target, relative=False, junction=True):
        path = self.drive / name
        path.mkdir(parents=True)
        try:
            set_attribute(path, 'user.WINEREPARSE', reparse(target, relative, junction))
        except OSError as error:
            self.skipTest(f'Fixture volume has no user xattrs: {error}')
        return path

    def test_decode_tags_and_malformed_buffers(self):
        self.assertEqual(decode_reparse(reparse(r'\??\C:\Game')), (r'\??\C:\Game', False))
        self.assertEqual(decode_reparse(reparse('Version', True, False)), ('Version', True))
        for data in [b'', b'bad' * 10, reparse('Game')[:-1], reparse('\0'), reparse('Game') + b'0' * 17000]:
            with self.subTest(data=data[:20]), self.assertRaises(ValueError):
                decode_reparse(data)

    def test_follows_junction_without_rewriting_the_stub(self):
        target = self.drive / 'Versions' / 'One'; target.mkdir(parents=True)
        game = target / 'Game.exe'; game.write_bytes(b'fixture')
        stub = self.stub('Current?', r'\??\C:\Versions\One')
        before = read_attribute(stub, 'user.WINEREPARSE')
        self.assertEqual(host_path(self.prefix, r'C:\Current\game.EXE'), game)
        self.assertEqual(host_path(self.prefix, 'drive_c/Current/Game.exe'), game)
        self.assertTrue(stub.is_dir()); self.assertFalse(stub.is_symlink())
        self.assertFalse((self.drive / 'Current').exists())
        self.assertEqual(read_attribute(stub, 'user.WINEREPARSE'), before)
        updated = self.drive / 'Versions' / 'Two'; updated.mkdir()
        set_attribute(stub, 'user.WINEREPARSE', reparse(r'\??\C:\Versions\Two'))
        self.assertEqual(host_path(self.prefix, r'C:\Current\Game.exe'), updated / 'Game.exe')

    def test_relative_link_and_remapped_drive(self):
        target = self.drive / 'Actual'; target.mkdir()
        self.stub('Current?', 'Actual', True, False)
        self.assertEqual(host_path(self.prefix, r'C:\Current\Game.exe'), target / 'Game.exe')
        (self.prefix / 'dosdevices').mkdir()
        external = self.root / 'external'; external.mkdir()
        (self.prefix / 'dosdevices' / 'd:').symlink_to(external)
        self.stub('External?', r'\??\D:\Game')
        self.assertEqual(host_path(self.prefix, r'C:\External\Game.exe'), external / 'Game' / 'Game.exe')

    def test_cycles_and_unmapped_targets_fail_explicitly(self):
        self.stub('Loop?', r'\??\C:\Loop')
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            host_path(self.prefix, r'C:\Loop\Game.exe')
        self.stub('Unmapped?', r'\??\D:\Game')
        with self.assertRaisesRegex(ValueError, 'not mapped'):
            host_path(self.prefix, r'C:\Unmapped\Game.exe')

    def test_missing_x86_builtin_is_not_hidden_by_x64_copy(self):
        binary = self.root / 'engine' / 'bin' / 'wine'; binary.parent.mkdir(parents=True); binary.touch()
        library = self.root / 'engine' / 'lib' / 'wine'
        for arch in ['i386-windows', 'x86_64-windows']:
            (library / arch).mkdir(parents=True)
        (library / 'x86_64-windows' / 'shcore.dll').touch()
        log = 'err:module:import_dll Library shcore.dll (which is needed by App.exe) not found'
        result = diagnose(binary, log)
        self.assertEqual([x['architecture_directory'] for x in result['missing_builtins']], ['i386-windows'])
        self.assertFalse(diagnose(binary, log, 'win64')['missing_builtins'])

    def test_game_dll_and_absent_layout_are_not_classified_as_engine_damage(self):
        binary = self.root / 'engine' / 'bin' / 'wine'
        game = diagnose(binary, 'err:module:import_dll Library SDL2.dll not found')
        self.assertFalse(game['missing_builtins']); self.assertEqual(game['other_libraries'], ['sdl2.dll'])
        unknown = diagnose(binary, 'err:module:import_dll Library shcore.dll not found', 'win32')
        self.assertFalse(unknown['missing_builtins']); self.assertTrue(unknown['notes'])


if __name__ == '__main__':
    unittest.main()
