// Lattice documentation site. `script/docs/build.sh` (`make doc`) stages the pages and builds it:
// `forge doc` regenerates the API reference (src/pages/src/) and ./vocs.sidebar.ts, and the guides are
// copied from docs/guides/, the storage Action README and PROGRESS.md, so each has one source.
import { defineConfig } from 'vocs/config'
import { sidebar as api } from './vocs.sidebar'

type Item = { text: string; link?: string; collapsed?: boolean; items?: Item[] }

const firstLink = (item: Item): string | undefined => item.link ?? item.items?.map(firstLink).find(Boolean)

const guides: Item = {
  text: 'Guides',
  items: [
    { text: 'Quickstart', link: '/' },
    { text: 'Compose your own Diamond', link: '/guides/compose-your-own-diamond' },
    { text: 'Selector compatibility', link: '/guides/selector-compatibility' },
    { text: 'Storage-safety Action', link: '/guides/storage-action' },
    { text: 'Hedera', link: '/guides/hedera' },
    { text: 'Grant evidence', link: '/grants' },
  ],
}

// One link per source folder of the generated reference.
const reference = (collapsed: boolean): Item => ({
  text: 'API reference',
  collapsed,
  items: (api as Item[]).map((section) => ({ text: section.text, link: firstLink(section) })),
})

export default defineConfig({
  title: 'Lattice',
  description: 'EIP-2535 Diamond modules with ERC-7201 namespaced storage',
  // GitHub Pages serves the project site under /lattice/.
  basePath: '/lattice',
  renderStrategy: 'full-static',
  socials: [{ icon: 'github', link: 'https://github.com/dadadave80/lattice' }],
  codeHighlight: {
    fallbackLanguage: 'plaintext',
    langs: [
      'ansi', 'bash', 'diff', 'html', 'js', 'json', 'jsx',
      'markdown', 'md', 'mdx', 'plaintext', 'rust', 'sol', 'solidity',
      'toml', 'ts', 'tsx', 'yaml', 'zsh',
    ],
  },
  // The full reference sidebar has ~900 links. Rendering it into every page made the site ~700 MB, so a
  // reference page shows only its own folder; the folder index stays one click away.
  sidebar: Object.fromEntries([
    ['/', [guides, reference(false)]],
    ...(api as Item[]).map((section) => [`/${section.text}`, [guides, reference(true), section]]),
  ]),
})
