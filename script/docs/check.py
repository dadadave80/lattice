#!/usr/bin/env python3
"""Check the site's entrypoints and their local navigation/assets without network access."""
from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

root = Path(sys.argv[1]).resolve()
pages = ['index.html', 'guides/quickstart/index.html', 'guides/storage-action/index.html',
         'src/contract.Lattice/index.html', 'src/governance/contract.Governor/index.html']
compose = root / 'guides/compose-your-own-diamond/index.html'
if compose.is_file():
    pages.insert(2, 'guides/compose-your-own-diamond/index.html')
errors = []
class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key not in ('href', 'src') or not value:
                continue
            url = urlsplit(value)
            if url.scheme or url.netloc or not url.path:
                continue
            target = (root / unquote(url.path.lstrip('/')) if url.path.startswith('/')
                      else page.parent / unquote(url.path)).resolve()
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
