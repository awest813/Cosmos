#!/usr/bin/env python3
"""Exercise the real reviewed recipe entry point with isolated fake runtimes."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReviewedRecipeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cosmos recipe ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.prefix = self.work / "selected prefix"
        self.prefix.mkdir()
        (self.prefix / "system.reg").write_text("#arch=win64\n")
        self.runtime = self.work / "selected runtime"
        self.bin = self.runtime / "Wine Devel.app/Contents/Resources/wine/bin"
        self.bin.mkdir(parents=True)
        self.marker = self.work / "calls.jsonl"
        fake = '''#!/usr/bin/env python3
import json, os, sys, subprocess
with open(os.environ['COSMOS_TEST_CALLS'], 'a') as f:
    f.write(json.dumps({'exe': sys.argv[0], 'args': sys.argv[1:], 'prefix': os.environ.get('WINEPREFIX'), 'wine': os.environ.get('WINE'), 'server': os.environ.get('WINESERVER'), 'arch': os.environ.get('WINEARCH'), 'override': os.environ.get('DLL_OVERRIDE')}) + '\\n')
if sys.argv[0].endswith('winetricks'):
    subprocess.run([os.environ['WINE'], '--fixture'], check=True)
'''
        for path in [self.bin / "wine", self.bin / "wineserver", self.work / "winetricks"]:
            path.write_text(fake)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.work) + os.pathsep + os.environ["PATH"],
                        WINEPREFIX=str(self.prefix), WINE_ROOT=str(self.runtime), WINE_VERSION="10.0",
                        COSMOS_BOTTLE="", COSMOS_BOTTLES_DIR=str(self.work / "Bottles"),
                        COSMOS_TEST_CALLS=str(self.marker), WINEARCH="win32", DLL_OVERRIDE="wrong=n",
                        WINE_BIN="/wrong/wine", WINE="/wrong/wine", WINESERVER="/wrong/server")
        self.env.pop("SCRIPT_DIR", None)

    def run_recipe(self, kind="dependency", identity="xact", revision=None):
        if revision is None:
            folder = "dependencies" if kind == "dependency" else "fixes"
            revision = hashlib.sha256((ROOT / "recipes" / folder / (identity + ".recipe")).read_bytes()).hexdigest()
        return subprocess.run([str(ROOT / "repair.command"), "reviewed-recipe", kind, identity, revision],
                              env=self.env, capture_output=True, text=True)

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.marker.exists(), "Rejected request executed Wine or winetricks")

    def test_dependency_uses_exact_runtime_and_prefix(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in self.marker.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]["args"], ["-q", "xact"])
        self.assertEqual(calls[1]["exe"], str(self.bin / "wine"))
        for call in calls:
            self.assertEqual(call["prefix"], str(self.prefix))
            self.assertEqual(call["wine"], str(self.bin / "wine"))
            self.assertEqual(call["server"], str(self.bin / "wineserver"))
            self.assertIsNone(call["arch"])

    def test_dll_fix_uses_reviewed_value(self):
        result = self.run_recipe("fix", "ddraw-override")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        call = json.loads(self.marker.read_text())
        self.assertEqual(call["exe"], str(self.bin / "wine"))
        self.assertIn("native,builtin", call["args"])
        self.assertEqual(call["override"], "ddraw=n,b")

    def test_stale_recipe_is_rejected(self):
        self.assert_rejected(self.run_recipe(revision="0" * 64))

    def test_uninitialized_environment_is_not_created(self):
        (self.prefix / "system.reg").unlink()
        self.assert_rejected(self.run_recipe())
        self.assertEqual(list(self.prefix.iterdir()), [])

    def test_missing_runtime_does_not_use_path_wine(self):
        (self.bin / "wine").unlink()
        self.assert_rejected(self.run_recipe())

    def test_destructive_recipe_is_rejected(self):
        self.assert_rejected(self.run_recipe("fix", "rebuild_prefix"))
        self.assertTrue((self.prefix / "system.reg").exists())

    def test_unavailable_named_environment_never_falls_back(self):
        self.env["COSMOS_BOTTLE"] = "missing"
        self.assert_rejected(self.run_recipe())

    def test_invalid_identity_is_rejected(self):
        self.assert_rejected(self.run_recipe(identity="../xact", revision="0" * 64))


if __name__ == "__main__":
    unittest.main()
