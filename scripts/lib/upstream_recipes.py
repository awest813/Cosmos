"""Translate curated CC0 Highball recipes into reviewable Cosmos plans.

Only recipes/ is read. ODbL predictions and MIT-derived anti-cheat data are not
included. Upstream verification remains upstream evidence, not a Cosmos result.
"""
import argparse
import json
import re
import sys
from pathlib import Path


def build_index(source, revision):
    source = Path(source)
    if 'CC0 1.0 Universal' not in (source / 'LICENSE').read_text():
        raise ValueError('Curated recipe license must be verified as CC0')
    entries = []
    for file in sorted(source.rglob('*.json')):
        recipe = json.loads(file.read_text())
        if not isinstance(recipe, dict) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]*', recipe.get('id', '')):
            continue
        entries.append({'recipe': recipe, 'source_revision': revision,
                        'source_url': f'https://github.com/gauthierpiarrette/highball-db/blob/{revision}/recipes/{file.relative_to(source).as_posix()}',
                        'license': 'CC0-1.0'})
    return {'schema': 'cosmos-upstream-recipes-v1', 'entries': entries}


def plan(entry, recipes_directory):
    recipe = entry['recipe']
    verbs_to_ids = {}
    for file in Path(recipes_directory).glob('*.recipe'):
        values = dict(line.split('=', 1) for line in file.read_text().splitlines() if '=' in line and not line.startswith('#'))
        for verb in values.get('WINETRICKS', '').split():
            verbs_to_ids[verb] = values.get('ID', file.stem)
    actions, manual = [], []
    for step in recipe.get('steps', []):
        if step.get('type') == 'winetricks':
            for verb in step.get('verbs', []):
                if verb in verbs_to_ids: actions.append('dep:' + verbs_to_ids[verb])
                else: manual.append({'reason': 'Dependency is not in the Cosmos catalog', 'verb': verb})
        elif step.get('type') != 'note':
            manual.append(step)
    return {'id': recipe['id'], 'title': recipe.get('title', recipe['id']),
            'source_url': entry['source_url'], 'source_revision': entry['source_revision'], 'license': entry['license'],
            'cosmos_test_result': 'untested', 'requires_review': True,
            'upstream_verification': recipe.get('lastVerified'),
            'requirements': recipe.get('requires', []), 'renderer': recipe.get('renderer'),
            'cosmos_dependency_recipes': sorted(set(actions)), 'manual_steps': manual,
            'notes': [step.get('text', '') for step in recipe.get('steps', []) if step.get('type') == 'note'],
            'known_issues': recipe.get('knownIssues', [])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--build-index')
    parser.add_argument('--recipe')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    root = Path(args.root)
    try:
        bundled = root / 'runtime/highball-recipes.json'
        source = root / 'third_party/highball-db'
        if args.build_index or not bundled.is_file():
            revision = '2b5c876308a39268189b12f391d07c34c5fb7c3e'
            provenance = source / 'COSMOS-UPSTREAM.txt'
            if provenance.is_file():
                match = re.search(r'^Commit: ([a-f0-9]{40})$', provenance.read_text(), re.M)
                if match: revision = match[1]
            index = build_index(source / 'recipes', revision)
        else: index = json.loads(bundled.read_text())
        if args.build_index:
            Path(args.build_index).write_text(json.dumps(index, ensure_ascii=False))
            return 0
        if not args.recipe:
            for entry in index['entries']:
                recipe = entry['recipe']; print(f"{recipe['id']}\t{recipe.get('title', '')}")
            return 0
        entry = next((item for item in index['entries'] if item['recipe']['id'] == args.recipe), None)
        if entry is None: raise ValueError('Unknown upstream recipe. List available ids with profile.command upstream-recipes.')
        result = plan(entry, root / 'recipes/dependencies')
        if args.json: print(json.dumps(result, indent=2))
        else:
            print(f"{result['title']} — upstream recipe review\nCosmos game status: UNTESTED\nSource: {result['source_url']}")
            print('Requirements: ' + ', '.join(result['requirements']))
            print('Suggested renderer: ' + (result['renderer'] or 'not specified'))
            print('Matching Cosmos dependency recipes: ' + (', '.join(result['cosmos_dependency_recipes']) or 'none'))
            print('Upstream verification (different engines/OS may be required): ' + json.dumps(result['upstream_verification']))
            print('Steps requiring manual review: ' + json.dumps(result['manual_steps']))
            print('Known upstream issues: ' + json.dumps(result['known_issues']))
            for note in result['notes']: print(note)
        return 0
    except (OSError, ValueError, KeyError) as error:
        print(f'Error: Upstream recipe review failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
