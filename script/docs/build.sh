#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build.sh
#
# Builds the documentation site (docs/site, Vocs) from the repository's own sources:
#   1. `forge doc --out docs/site` regenerates the API reference pages (src/pages/src/) and
#      vocs.sidebar.ts. It leaves the committed package.json and vocs.config.ts alone.
#   2. The hand-written pages are copied in, so each keeps a single source:
#        docs/guides/quickstart.md                -> /                (home page)
#        docs/guides/<guide>.md                   -> /guides/<guide>
#        .github/actions/storage-layout/README.md -> /guides/storage-action
#        PROGRESS.md                              -> /grants
#      Links between these pages become site routes; any other repository-relative link becomes a
#      GitHub permalink at the checked-out commit, matching forge doc's "Git Source" links.
#   3. `npm ci` installs the pinned Vocs toolchain (docs/site/package-lock.json), `vocs build` writes
#      the static site to docs/site/dist/public, and script/docs/check-links.sh checks it.
#
# Usage:
#   script/docs/build.sh          # stage, build and check (`make doc`)
#   script/docs/build.sh --serve  # stage, then run the Vocs dev server (`make doc-serve`)
#
# Requires forge (the shared pinned release), git, perl, Node.js >= 22.15 and npm. Not a Solidity gate.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
SITE="docs/site"
PAGES="${SITE}/src/pages"
REPO_URL="https://github.com/dadadave80/lattice"

for tool in forge git perl node npm; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: ${tool} not found on PATH" >&2; exit 2; }
done

forge doc --out "${SITE}"
# forge doc writes README.md as the home page; the quickstart replaces it.
rm -f "${PAGES}/index.mdx"
rm -rf "${PAGES}/guides" "${PAGES}/grants.md"
mkdir -p "${PAGES}/guides"

COMMIT="$(git rev-parse HEAD)"
# "<source> <route>" for every copied page. Links to these sources become routes.
ROUTES="docs/guides/quickstart.md /
docs/guides/compose-your-own-diamond.md /guides/compose-your-own-diamond
docs/guides/selector-compatibility.md /guides/selector-compatibility
docs/guides/hedera.md /guides/hedera
.github/actions/storage-layout/README.md /guides/storage-action
PROGRESS.md /grants"

while read -r source route; do
    [[ -f "${source}" ]] || { echo "ERROR: missing page source ${source}" >&2; exit 2; }
    if [[ "${route}" == "/" ]]; then dest="${PAGES}/index.md"; else dest="${PAGES}${route}.md"; fi
    ROUTES="${ROUTES}" SOURCE="${source}" BLOB="${REPO_URL}/blob/${COMMIT}" perl -0pe '
        BEGIN {
            %route = map { split / / } split /\n/, $ENV{ROUTES};
            ($dir = $ENV{SOURCE}) =~ s{[^/]*$}{};
        }
        sub resolve {
            my ($target) = @_;
            return $target if $target =~ m{^([a-z][a-z0-9+.-]*:|#|/)}i;
            my ($path, $frag) = $target =~ /^([^#]*)(#.*)?$/;
            $frag //= "";
            my @out;
            for my $part (split m{/}, $dir . $path) {
                next if $part eq "" || $part eq ".";
                if ($part eq "..") { pop @out } else { push @out, $part }
            }
            my $repo_path = join "/", @out;
            return ($route{$repo_path} // "$ENV{BLOB}/$repo_path") . $frag;
        }
        # Inline links and images, ](target) and ](target "title"), outside fenced and inline code.
        my @chunks = map { /^[ \t]*```/ ? $_ : split /(`[^`\n]*`)/ } split /(^[ \t]*```.*?^[ \t]*```[^\n]*\n)/ms;
        for (@chunks) { s/\]\(([^)\s]+)/"](" . resolve($1)/ge unless /^[ \t]*`/ }
        $_ = join "", @chunks;
    ' "${source}" >"${dest}"
done <<<"${ROUTES}"

cd "${SITE}"
# npm ci reinstalls from scratch; skip it while node_modules is newer than the lockfile.
if [[ ! node_modules/.package-lock.json -nt package-lock.json ]]; then
    npm ci --no-audit --no-fund
fi
if [[ "${1:-}" == "--serve" ]]; then
    exec npm run dev
fi
rm -rf dist
npm run build
cd "${ROOT}"
./script/docs/check-links.sh "${SITE}/dist/public"
