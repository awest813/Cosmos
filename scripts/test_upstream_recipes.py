#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from lib.upstream_recipes import build_index, plan


class UpstreamRecipeTests(unittest.TestCase):
    def test_curated_snapshot_has_pinned_provenance_and_separate_license(self):
        root = Path(__file__).resolve().parent.parent
        revision = '2b5c876308a39268189b12f391d07c34c5fb7c3e'
        index = build_index(root / 'third_party/highball-db/recipes', revision)
        entries = index['entries']
        self.assertEqual(len(entries), len({e['recipe']['id'] for e in entries}))
        self.assertGreater(len(entries), 40)
        for entry in entries:
            self.assertEqual(entry['license'], 'CC0-1.0')
            self.assertIn(f'/{revision}/recipes/', entry['source_url'])
            result = plan(entry, root / 'recipes/dependencies')
            self.assertEqual(result['cosmos_test_result'], 'untested')
            self.assertTrue(result['requires_review'])

    def test_unknown_dependencies_and_non_dependency_steps_require_manual_review(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'audio.recipe').write_text('ID=audio\nWINETRICKS=xact\n')
            custom = {'type': 'registry', 'key': 'fixture'}
            recipe = {'id': 'fixture', 'requires': ['macOS 26'], 'renderer': 'dxmt',
                      'lastVerified': {'result': 'works'}, 'steps': [
                          {'type': 'winetricks', 'verbs': ['xact', 'unknown-verb']},
                          custom, {'type': 'note', 'text': 'Check the original requirements'}]}
            result = plan({'recipe': recipe, 'source_url': 'fixture',
                           'source_revision': 'fixture', 'license': 'CC0-1.0'}, directory)
            self.assertEqual(result['cosmos_dependency_recipes'], ['dep:audio'])
            self.assertEqual(result['manual_steps'][0]['verb'], 'unknown-verb')
            self.assertIn(custom, result['manual_steps'])
            self.assertEqual(result['requirements'], ['macOS 26'])
            self.assertEqual(result['upstream_verification'], {'result': 'works'})
            self.assertEqual(result['cosmos_test_result'], 'untested')
            self.assertEqual(result['notes'], ['Check the original requirements'])


if __name__ == '__main__': unittest.main()
