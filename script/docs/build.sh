#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
DOCS_FORGE="${DOCS_FORGE:-forge}"
"$DOCS_FORGE" --version | head -1 | grep -q '1.8.1' || { echo 'Docs require Forge v1.8.1'; exit 1; }
"$DOCS_FORGE" doc --out docs/.generated
python3 - <<'PY'
from pathlib import Path
site = Path('docs/.generated/src/pages')
guides = site / 'guides'
guides.mkdir(exist_ok=True)
quickstart = Path('docs/guides/quickstart.md').read_text()
compose = Path('docs/guides/compose-your-own-diamond.md')
if not compose.is_file():
    quickstart = quickstart.replace('[composition guide](compose-your-own-diamond.md)',
                                    'the composition guide supplied by Milestone 2')
(guides / 'quickstart.mdx').write_text(quickstart)
(guides / 'storage-action.mdx').write_text(Path('.github/actions/storage-layout/README.md').read_text())
if compose.is_file():
    (guides / 'compose-your-own-diamond.mdx').write_text(compose.read_text())
sidebar = Path('docs/.generated/vocs.sidebar.ts')
items = [
    '    { text: "Quickstart", link: "/guides/quickstart" },',
    '    { text: "Storage Action", link: "/guides/storage-action" },',
]
if compose.is_file():
    items.insert(1, '    { text: "Compose your own Diamond", link: "/guides/compose-your-own-diamond" },')
sidebar.write_text(sidebar.read_text().replace(
    'export const sidebar = [',
    'export const sidebar = [\n  { text: "Guides", items: [\n' + '\n'.join(items) + '\n  ] },', 1))
PY
(cd docs/.generated && npm install --legacy-peer-deps --no-audit --no-fund && npm run build)
python3 script/docs/check.py docs/.generated/dist
