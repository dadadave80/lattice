#!/usr/bin/env python3
"""Source-bound ERC-7201 snapshots and conservative append-only compatibility checks."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def same_solidity(before, after):
    # Canonical formatting preserves literals; stripping whitespace would not.
    return run(['forge', 'fmt', '--raw', '-'], input=before) == run(
        ['forge', 'fmt', '--raw', '-'], input=after)


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def shape(types, key, active=()):
    require(key in types, f"Missing layout type: {key}")
    t = types[key]
    result = {k: t[k] for k in ('encoding', 'label', 'numberOfBytes')}
    if key in active:
        return {'recursive': t['label']}
    active = (*active, key)
    for child in ('base', 'key', 'value'):
        if child in t:
            result[child] = shape(types, t[child], active)
    if 'members' in t:
        require(t['members'], f"Empty struct: {t['label']}")
        result['members'] = [dict(label=m['label'], slot=str(int(m['slot'])), offset=int(m['offset']),
                                  type=shape(types, m['type'], active)) for m in t['members']]
    return result


def snapshot(manifest, layout, probe_ast, source_asts):
    require(isinstance(manifest, list) and manifest, 'Manifest must be a nonempty list')
    require(layout.get('storage') and layout.get('types'), 'Empty storage layout')
    variables = {n['name']: n for n in walk(probe_ast)
                 if n.get('nodeType') == 'VariableDeclaration' and n.get('stateVariable')}
    fields = {v['label']: v for v in layout['storage']}
    result = {}
    seen = set()
    enums = {n.get('canonicalName', n['name']): [m['name'] for m in n['members']]
             for a in source_asts.values() for n in walk(a) if n.get('nodeType') == 'EnumDefinition'}
    for e in manifest:
        ns, var = e['namespace'], e['variable']
        require(ns and ns not in result and var not in seen, f'Duplicate namespace/variable: {ns}/{var}')
        seen.add(var)
        require(var in fields and var in variables, f'Missing probe variable: {var}')
        ast = source_asts[e['source']]
        nodes = list(walk(ast))
        structs = [n for n in nodes if n.get('nodeType') == 'StructDefinition' and n.get('name') == e['type']]
        require(len(structs) == 1, f"Ambiguous/missing source struct: {e['source']}:{e['type']}")
        struct = structs[0]
        require(variables[var]['typeName']['referencedDeclaration'] == struct['id'],
                f'{ns}: probe must import the actual source struct (no mirrors)')
        doc = struct.get('documentation', {})
        doc = doc.get('text', '') if isinstance(doc, dict) else doc
        declared = re.findall(r'@custom:storage-location\s+erc7201:([^\s]+)', doc or '')
        require(declared == [ns], f'{ns}: source namespace annotation mismatch')
        constants = [n for n in nodes if n.get('nodeType') == 'VariableDeclaration'
                     and n.get('constant') and n.get('name') == e['slot-constant']]
        require(len(constants) == 1, f'{ns}: missing/ambiguous slot constant')
        value = constants[0].get('value', {})
        require(value.get('nodeType') == 'Literal' and value.get('kind') == 'number',
                f'{ns}: slot constant must be a literal')
        slot = int(value['value'], 0)
        expected = int(run(['cast', 'index-erc7201', ns]), 16)
        require(slot == expected, f'{ns}: slot constant differs from ERC-7201 namespace')
        t = shape(layout['types'], fields[var]['type'])
        require(t.get('members'), f'{ns}: no members')
        # Enums have a stable layout width but changing their order changes stored meaning.
        for member in walk(t):
            label = member.get('label', '')
            if label.startswith('enum '):
                require(label[5:] in enums, f'{ns}: enum definition unavailable: {label}')
                member['enum-members'] = enums[label[5:]]
        result[ns] = dict(source=e['source'], type=e['type'], slot=f'0x{slot:064x}', layout=t)
    return {'version': 1, 'namespaces': result}


def compatible(old, new):
    require(old.get('version') == new.get('version') == 1, 'Unsupported snapshot version')
    require(old.get('namespaces') and new.get('namespaces'), 'Empty baseline')
    for ns, before in old['namespaces'].items():
        require(ns in new['namespaces'], f'{ns}: namespace removed')
        after = new['namespaces'][ns]
        for k in ('source', 'type', 'slot'):
            require(before[k] == after[k], f'{ns}: {k} changed: {before[k]} -> {after[k]}')
        a, b = before['layout'], after['layout']
        require(a['encoding'] == b['encoding'] and a['label'] == b['label'], f'{ns}: root type changed')
        require(a.get('members') and b.get('members'), f'{ns}: empty members')
        require(len(b['members']) >= len(a['members']), f'{ns}: fields removed')
        for index, field in enumerate(a['members']):
            candidate = b['members'][index]
            require(field == candidate,
                    f"{ns}.{field['label']}: incompatible field/nested type\n"
                    f"  old: {json.dumps(field, sort_keys=True)}\n  new: {json.dumps(candidate, sort_keys=True)}")
        require(int(b['numberOfBytes']) >= int(a['numberOfBytes']), f'{ns}: root shrank')
        # Compiler-generated member positions enforce packing; only a top-level tail may grow.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--working-directory', default='.')
    parser.add_argument('--probe', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--baseline-ref')
    parser.add_argument('--foundry-profile', default='ci')
    parser.add_argument('--update', action='store_true')
    args = parser.parse_args()
    os.chdir(args.working_directory)
    os.environ['FOUNDRY_PROFILE'] = args.foundry_profile
    manifest = json.loads(Path(args.manifest).read_text())
    source, contract = args.probe.rsplit(':', 1)
    # One isolated compiler invocation: incremental artifacts can carry unrelated AST IDs.
    with tempfile.TemporaryDirectory(prefix='storage-guard-') as temp:
        out = Path(temp) / 'out'
        subprocess.run(['forge', 'build', source, '--ast', '--extra-output', 'storageLayout',
                        '--out', str(out), '--cache-path', str(Path(temp) / 'cache')],
                       check=True, stdout=sys.stderr)
        artifact = json.loads((out / Path(source).name / (contract + '.json')).read_text())
        asts = {}
        for p in out.glob('*/*.json'):
            data = json.loads(p.read_text())
            ast = data.get('ast')
            if ast:
                asts[ast['absolutePath']] = ast
        current = snapshot(manifest, artifact['storageLayout'], artifact['ast'], asts)
    baseline = Path(args.baseline)
    if args.baseline_ref:
        root = Path(run(['git', 'rev-parse', '--show-toplevel'])).resolve()
        relative = baseline.resolve().relative_to(root).as_posix()
        ref = run(['git', 'rev-parse', '--verify', '--end-of-options', args.baseline_ref + '^{commit}'])
        text = run(['git', 'show', f'{ref}:{relative}'])
        if text.startswith('### '):
            require(relative == 'script/upgrades/storage-layout.baseline' and source ==
                    'script/upgrades/StorageLayoutProbe.sol', 'Legacy format is only supported for Lattice migration')
            # One-time migration permits formatting only; dependencies must remain identical.
            old_names = set(re.findall(r'^### \w+ @ erc7201:([^\s]+)', text, re.M))
            require(old_names and old_names <= current['namespaces'].keys(), 'Legacy namespaces missing')
            changed = run(['git', 'diff', '--name-only', '-z', ref, '--', 'src', 'lib'])
            for path in filter(None, changed.split('\0')):
                require(path.startswith('src/') and path.endswith('.sol') and Path(path).is_file()
                        and not Path(path).is_symlink(), 'Legacy migration changed source/dependency: ' + path)
                before = run(['git', 'show', f'{ref}:{path}'])
                require(same_solidity(before, Path(path).read_text()),
                        'Legacy migration requires unchanged Solidity: ' + path)
        else:
            compatible(json.loads(text), current)
    if args.update:
        require(not os.environ.get('GITHUB_ACTIONS'), 'Baseline updates are local only')
        baseline.write_text(json.dumps(current, indent=2, sort_keys=True) + '\n')
        print(f'Wrote {baseline}; review and commit the diff.')
    else:
        committed = json.loads(baseline.read_text())
        require(committed == current, 'Snapshot drift: regenerate locally with --update and review the diff')
        print(f"OK: {len(current['namespaces'])} source-bound namespaces; "
              + ('trusted-baseline compatibility verified' if args.baseline_ref else 'snapshot matches (no historical comparison)'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Storage guard failed: {exc}', file=sys.stderr)
        sys.exit(1)
