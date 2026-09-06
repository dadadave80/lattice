#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
DOCS_FORGE="${DOCS_FORGE:-forge}"
"$DOCS_FORGE" --version | head -1 | grep -q '1.7.0' || { echo 'Docs require Forge v1.7.0 (mdBook output)'; exit 1; }
mdbook --version | grep -q '0.4.51' || { echo 'Docs require mdbook v0.4.51'; exit 1; }
"$DOCS_FORGE" doc --out docs/.generated
python3 - <<'PY'
from pathlib import Path
import shutil
import os
import re
book = Path('docs/.generated')
(book / 'src/guides').mkdir(exist_ok=True)
for name in ('quickstart', 'compose-your-own-diamond'):
    shutil.copyfile(f'docs/guides/{name}.md', book / f'src/guides/{name}.md')
shutil.copyfile('.github/actions/storage-layout/README.md', book / 'src/guides/storage-action.md')
# forge-doc emits root-relative intra-reference links; make them safe for /lattice/ hosting.
for page in (book / 'src').rglob('*.md'):
    text = page.read_text()
    text = re.sub(r'\]\(/(src/[^)#]+)(#[^)]*)?\)',
                  lambda m: '](' + os.path.relpath(book / 'src' / m[1], page.parent) + (m[2] or '') + ')', text)
    page.write_text(text)
p = book / 'src/SUMMARY.md' 
s = p.read_text()
s = s.replace('# src', '# Guides\n- [Quickstart](guides/quickstart.md)\n- [Compose your own Diamond](guides/compose-your-own-diamond.md)\n- [Storage Action](guides/storage-action.md)\n# API reference', 1)
p.write_text(s)
p = book / 'book.toml'
p.write_text(p.read_text().replace('title = ""', 'title = "Lattice"'))
# The root repository README contains repo-relative links; the book home is a focused entrypoint.
(book / 'src/README.md').write_text('# Lattice\n\n[Quickstart](guides/quickstart.md) · [Compose your own Diamond](guides/compose-your-own-diamond.md) · [Storage Action](guides/storage-action.md)\n\nSolidity modules for governance-upgradeable Diamonds. Unaudited; use test assets.\n')
PY
mdbook build docs/.generated
python3 script/docs/check.py docs/.generated/book
