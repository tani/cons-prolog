#!/usr/bin/env python3
"""Development-only regeneration from the bundled, pinned Logtalk sources.

SWI-Prolog is needed only here to read Logtalk source syntax, never to execute
or judge the tests. Normal validation uses the checked-in port and SBCL only.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REVISION = 'e0f2576eef32aa5d5732a0d47531d0f62b9a31f1'


def digests(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swipl', default='swipl')
    args = parser.parse_args()
    lock_path = HERE / 'upstream.json'
    if lock_path.exists():
        previous = json.loads(lock_path.read_text())
        if previous.get('revision') != REVISION or previous['files']['vendor/logtalk'] != digests(HERE / 'vendor/logtalk'):
            raise ValueError('Bundled originals differ from the pinned sources; review source updates explicitly')
    subprocess.run([args.swipl, '-q', '-f', str(HERE / 'port-logtalk.pl'), '--',
                    str(HERE / 'vendor/logtalk/tests/prolog'), str(HERE / 'suite')], check=True)
    path = HERE / 'suite/cases.json'
    cases = json.loads(path.read_text())
    # The upstream retract examples intentionally consume clauses across tests.
    by_name = {c['name']: c for c in cases if not c['skip']}
    dependencies = {'iso_retract_1_04': ['iso_retract_1_01', 'iso_retract_1_03'],
                    'iso_retract_1_05': ['iso_retract_1_01', 'iso_retract_1_03', 'iso_retract_1_04']}
    for name, previous in dependencies.items():
        by_name[name]['predecessors'] = [by_name[p]['id'] for p in previous]
    for case in cases:
        lines = (HERE / 'vendor/logtalk/tests/prolog' / case['source']).read_text().splitlines()
        references = [line.strip('% \t') for line in lines[:case['line']+1]
                      if re.search(r'(section |standard,|Corrigendum)', line, re.I)]
        case['standard_reference'] = references[-1] if references else 'ISO/IEC 13211-1 and corrigenda; see upstream source comments'
        case['classification'] = ('undefined' if 'undefined' in case['skip'] else
                                  'upstream_disabled' if case['skip'] else 'standard_example')
        if case['expected'] != case['upstream_expected']:
            case['adaptation'] = 'Select the standard first exception alternative; discard compatibility alternatives'
    by_name['iso_setof_3_17']['adaptation'] = ('ISO 7.2 permits either relative variable order: move the alternative inside the success branch instead of an unreachable else')
    if len(cases) != 782 or len({c['source'] for c in cases}) != 93:
        raise ValueError('Unexpected source inventory')
    path.write_text(json.dumps(cases, ensure_ascii=False, indent=2) + '\n')
    lock = {'repository': 'LogtalkDotOrg/logtalk3', 'revision': REVISION,
            'license': 'Apache-2.0', 'selection': 'All iso_ test definitions, including disabled and alternate branches',
            'cases': len(cases), 'source_files': 93,
            'files': {'vendor/logtalk': digests(HERE / 'vendor/logtalk'), 'suite': digests(HERE / 'suite')}}
    (HERE / 'upstream.json').write_text(json.dumps(lock, indent=2) + '\n')
    print(f'Regenerated {len(cases)} definitions from bundled sources')


if __name__ == '__main__':
    main()
