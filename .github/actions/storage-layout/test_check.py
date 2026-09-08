#!/usr/bin/env python3
"""Run the storage guard's regression checks using Python's standard library."""
import copy
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('guard', Path(__file__).with_name('check.py'))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


def rejects(fn):
    try:
        fn()
    except (ValueError, KeyError):
        return
    raise AssertionError('Unsafe input was accepted')


def main():
    source = 'contract Example { string constant LABEL = "a b"; uint256 value; }'
    assert g.same_solidity(source, source.replace('; ', ';\n'))
    assert not g.same_solidity(source, source.replace('a b', 'ab'))
    assert not g.same_solidity(source, source.replace('uint256', 'uint128'))
    root = Path(__file__).resolve().parents[3]
    old = json.loads((root / 'script/upgrades/storage-layout.baseline').read_text())
    g.compatible(old, copy.deepcopy(old))
    ns = 'lattice.storage.GovernedDiamondCut'
    def mutated(change):
        new = copy.deepcopy(old)
        change(new['namespaces'][ns])
        return new
    appended = mutated(lambda n: n['layout']['members'].append(
        dict(label='_tail', slot='99', offset=0, type={'encoding':'inplace','label':'uint256','numberOfBytes':'32'})))
    appended['namespaces'][ns]['layout']['numberOfBytes'] = '3200'
    g.compatible(old, appended)
    for change in (
        lambda n: n.update(slot='0x00'),
        lambda n: n['layout']['members'].reverse(),
        lambda n: n['layout']['members'].pop(),
        lambda n: n['layout']['members'][0].update(offset=1),
        lambda n: n['layout']['members'][0]['type'].update(numberOfBytes='16'),
        lambda n: n['layout']['members'][1]['type']['key'].update(label='address'),
        lambda n: n['layout']['members'][1]['type']['value']['members'].reverse(),
    ):
        rejects(lambda change=change: g.compatible(old, mutated(change)))
    removed = copy.deepcopy(old)
    del removed['namespaces'][ns]
    rejects(lambda: g.compatible(old, removed))
    rejects(lambda: g.compatible({'version':1,'namespaces':{}}, old))
    rejects(lambda: g.snapshot([], {}, {}, {}))
    rejects(lambda: g.shape({}, 'missing'))
    first = {'a123': {'encoding':'inplace','label':'uint256','numberOfBytes':'32'}}
    second = {'a456': first['a123']}
    assert g.shape(first, 'a123') == g.shape(second, 'a456')
    print('Storage compatibility regression checks passed')


def consumer_checks():
    """Compile a real independent consumer and mutate source, probe, metadata and history."""
    with tempfile.TemporaryDirectory(prefix='storage guard ') as temp:
        root = Path(temp)
        (root / 'src').mkdir()
        (root / 'script').mkdir()
        (root / 'foundry.toml').write_text('[profile.default]\nsolc = "0.8.36"\n')
        source = """// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
bytes32 constant SLOT = 0x63a53815bfe44493ce6b602e02e6290b640027f8562f45263d0368a4174da300;
struct Position { uint256 amount; uint256 epoch; }
/// @custom:storage-location erc7201:example.storage.Vault
struct VaultStorage { uint256 total; mapping(address => Position) positions; }
library VaultLib {}
"""
        probe = '// SPDX-License-Identifier: MIT\npragma solidity ^0.8.34;\nimport {VaultStorage} from "src/Vault.sol";\ncontract Probe { VaultStorage internal vault; }\n'
        (root / 'src/Vault.sol').write_text(source)
        (root / 'script/Probe.sol').write_text(probe)
        manifest = [dict(variable='vault', source='src/Vault.sol', type='VaultStorage',
                         namespace='example.storage.Vault', **{'slot-constant':'SLOT'})]
        (root / 'manifest.json').write_text(json.dumps(manifest))
        checker = str(Path(__file__).with_name('check.py').resolve())
        cmd = [sys.executable, checker, '--working-directory', str(root), '--probe',
               'script/Probe.sol:Probe', '--manifest', 'manifest.json', '--baseline',
               'baseline.json', '--foundry-profile', 'default']
        env = dict(os.environ)
        env.pop('GITHUB_ACTIONS', None)  # fixture updates are local subprocesses, never repository writes
        def check(*flags, ok=True, contains=None):
            result = subprocess.run([*cmd, *flags], text=True, capture_output=True, env=env)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            if contains:
                assert contains in result.stdout + result.stderr, result.stdout + result.stderr
        check('--update')
        original = (root / 'baseline.json').read_text()
        check()
        def git(*args):
            return subprocess.check_output(['git', '-C', str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()
        git('init', '-q')
        git('add', 'src', 'script', 'foundry.toml', 'manifest.json', 'baseline.json')
        git('-c', 'user.name=Storage fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Trusted seed')
        base = git('rev-parse', 'HEAD')
        # A source-only change must fail even with an untouched source-importing probe.
        (root / 'src/Vault.sol').write_text(source.replace('uint256 amount; uint256 epoch;', 'uint256 epoch; uint256 amount;'))
        check(ok=False, contains='Snapshot drift')
        check('--update')
        check('--baseline-ref', base, ok=False, contains='incompatible field/nested type')
        # Safe top-level append needs a fresh snapshot but preserves the historical layout.
        (root / 'src/Vault.sol').write_text(source.replace('positions; }', 'positions; uint256 tail; }'))
        check(ok=False)
        check('--update', '--baseline-ref', base)
        check('--baseline-ref', base)
        (root / 'src/Vault.sol').write_text(source)
        (root / 'baseline.json').write_text(original)
        # A source namespace edit and a slot-constant edit each fail before snapshot comparison.
        (root / 'src/Vault.sol').write_text(source.replace('example.storage.Vault', 'example.storage.Other'))
        check(ok=False, contains='annotation mismatch')
        (root / 'src/Vault.sol').write_text(source.replace('0x63a538', '0x73a538'))
        check(ok=False, contains='slot constant differs')
        (root / 'src/Vault.sol').write_text(source)
        # A handwritten mirror with identical fields is still rejected.
        (root / 'script/Probe.sol').write_text(probe.replace('import {VaultStorage} from "src/Vault.sol";',
            'import {Position} from "src/Vault.sol"; struct VaultStorage { uint256 total; mapping(address => Position) positions; }'))
        check(ok=False, contains='no mirrors')
        (root / 'script/Probe.sol').write_text(probe)
        (root / 'manifest.json').write_text(json.dumps(manifest * 2))
        check(ok=False, contains='Duplicate namespace')
        (root / 'manifest.json').write_text('[]')
        check(ok=False, contains='nonempty list')
        (root / 'manifest.json').write_text(json.dumps(manifest))
        (root / 'baseline.json').unlink()
        check(ok=False)
        (root / 'baseline.json').write_text('not json')
        check(ok=False)
    print('Independent consumer, source mutation, metadata, and trusted-history checks passed')


if __name__ == '__main__':
    main()
    consumer_checks()
