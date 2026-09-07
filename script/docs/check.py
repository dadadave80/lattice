#!/usr/bin/env python3
"""Check the site's entrypoints and their local navigation/assets without network access."""
from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

root = Path(sys.argv[1]).resolve()
pages = ['index.html', 'guides/quickstart.html', 'guides/compose-your-own-diamond.html',
         'guides/storage-action.html', 'src/Lattice.sol/contract.Lattice.html',
         'src/governance/Governor.sol/contract.Governor.html']
errors = []
class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key not in ('href', 'src') or not value:
                continue
            url = urlsplit(value)
            if url.scheme or url.netloc or not url.path:
                continue
            target = (page.parent / unquote(url.path)).resolve()
            if not target.is_relative_to(root) or not target.exists():
                errors.append(f'{page.relative_to(root)}: missing local target {value}')
for name in pages:
    page = root / name
    if not page.is_file():
        errors.append(f'Missing page {name}')
        continue
    Links().feed(page.read_text())
if errors:
    raise SystemExit('\n'.join(sorted(set(errors))))
print('Docs entrypoints, local navigation and assets passed')
