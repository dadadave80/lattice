// Lattice documentation site. `script/docs/build.sh` (`make doc`) stages the pages and builds it:
// `forge doc` regenerates the API reference (src/pages/src/) and ./vocs.sidebar.ts, and the guides are
// copied from docs/guides/, the storage Action README, PROGRESS.md and docs/adr/, so each has one source.
import { defineConfig } from 'vocs/config'
import { sidebar as api } from './vocs.sidebar'

type Item = { text: string; link?: string; collapsed?: boolean; items?: Item[] }

const firstLink = (item: Item): string | undefined => item.link ?? item.items?.map(firstLink).find(Boolean)

// One entry per record in docs/adr/; its README lists them too, and script/docs/check-links.sh
// fails when one is missing here.
const decisions: Item = {
  text: 'Design decisions',
  collapsed: true,
  items: [
    { text: 'Index', link: '/adr' },
    { text: '0001 Three-file modules', link: '/adr/0001-three-file-pattern' },
    { text: '0002 ERC-7201 storage', link: '/adr/0002-erc7201-namespaced-storage' },
    { text: '0003 ERC-165 map slots', link: '/adr/0003-precomputed-erc165-slots' },
    { text: '0004 Release salts', link: '/adr/0004-release-deployer-and-salts' },
    { text: '0005 Receive facet', link: '/adr/0005-receive-facet' },
    { text: '0006 Atomic initialization', link: '/adr/0006-atomic-factory-initialization' },
    { text: '0007 Registry trust', link: '/adr/0007-registry-trust-model' },
    { text: '0008 Freeze once live', link: '/adr/0008-freeze-once-live' },
    { text: '0009 Token hook model', link: '/adr/0009-token-extension-hook-model' },
    { text: '0010 Groth16 on BN254', link: '/adr/0010-groth16-bn254' },
    { text: '0011 No utility duplicates', link: '/adr/0011-no-stateless-utility-duplicates' },
    { text: '0012 Bash storage checker', link: '/adr/0012-storage-checker-bash-jq' },
  ],
}

const guides: Item = {
  text: 'Guides',
  items: [
    { text: 'Quickstart', link: '/' },
    { text: 'Compose your own Diamond', link: '/guides/compose-your-own-diamond' },
    { text: 'Selector compatibility', link: '/guides/selector-compatibility' },
    { text: 'Storage-safety Action', link: '/guides/storage-action' },
    { text: 'Hedera', link: '/guides/hedera' },
    { text: 'Grant evidence', link: '/grants' },
    decisions,
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
