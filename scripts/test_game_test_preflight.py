#!/usr/bin/env python3
import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('game_test_preflight.py'))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


def make_pe(path, machine=0x14c, dll=False):
    data = bytearray(512)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<H', data, 132, machine)
    struct.pack_into('<H', data, 150, 0x2000 if dll else 2)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


class PreflightTests(unittest.TestCase):
    def test_spock_architecture_and_unknown_result(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exe, wine, mvk = root/'Game With Spaces/game.exe', root/'wine', root/'MoltenVK.dylib'
            make_pe(exe)
            wine.write_text('not executed'); wine.chmod(0o755)
            mvk.touch(); (root/'system.reg').touch()
            dll = root/'spock/x86/d3d9.dll'
            make_pe(dll, machine=0x8664, dll=True)
            report = preflight.inspect(exe, root, wine, 'spockd3d9', root/'spock', mvk)
            self.assertFalse(report['preflight_passed'])
            make_pe(dll, dll=True)
            report = preflight.inspect(exe, root, wine, 'spockd3d9', root/'spock', mvk)
            self.assertTrue(report['preflight_passed'])
            self.assertEqual(report['game_result'], 'untested')
            self.assertIsNone(report['observations']['backend_loaded'])
            (exe.parent/'d3d9.dll').touch()
            self.assertTrue(any('game folder' in warning for warning in
                                preflight.inspect(exe, root, wine, 'recommended')['warnings']))

    def test_32_bit_game_and_prefix_architecture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exe, wine = root/'game.exe', root/'wine'
            make_pe(exe)
            wine.touch(); wine.chmod(0o755)
            (root/'system.reg').write_text('WINE REGISTRY Version 2\n#arch=win64\n')
            report = preflight.inspect(exe, root, wine, 'wined3d')
            self.assertTrue(report['preflight_passed'])
            self.assertTrue(any('WoW64 support' in warning for warning in report['warnings']))
            (root/'system.reg').write_text('WINE REGISTRY Version 2\r\n#arch=win32\r\n')
            self.assertTrue(preflight.inspect(exe, root, wine, 'wined3d')['preflight_passed'])
            make_pe(exe, machine=0x8664)
            report = preflight.inspect(exe, root, wine, 'wined3d')
            self.assertFalse(report['preflight_passed'])
            self.assertEqual(report['prefix_architecture'], 'win32')

    def test_missing_or_invalid_files_block(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertIsNone(preflight.pe_kind(root/'missing.exe'))
            self.assertFalse(preflight.inspect(root/'missing.exe', root, root/'wine', 'recommended')['preflight_passed'])
            dll = root/'wrong.exe'
            make_pe(dll, dll=True)
            self.assertFalse(preflight.inspect(dll, root, root/'wine', 'recommended')['checks'][0]['passed'])


if __name__ == '__main__':
    unittest.main()
