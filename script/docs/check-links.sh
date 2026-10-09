#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-links.sh
#
# Offline check of the built documentation site (script/docs/build.sh runs it):
#   - the pages the site promises exist: home, every guide, the grant evidence, the decision-record
#     index and every record in docs/adr/, and representative API reference pages;
#   - every record in docs/adr/ is linked from the Design decisions sidebar in docs/site/vocs.config.ts;
#   - every local href/src in every HTML page resolves to a built file. The site is served under the
#     /lattice base path, so a root-absolute link must start with /lattice/; one that does not would
#     404 on GitHub Pages.
# External links (with a scheme or //host) are not fetched.
#
# Known exception: Vocs 2.10.0 renders each page's "skip to content" link as `<path>#vocs-content`
# without the base path. It is a keyboard-only skip link to the current page, so it is ignored.
#
# Usage: script/docs/check-links.sh docs/site/dist/public [base-path]   (base path defaults to /lattice)
# ---------------------------------------------------------------------------
set -euo pipefail
export LC_ALL=C

DIR="${1:?usage: check-links.sh <built-site-dir> [base-path]}"
BASE="${2:-/lattice}"
[[ -d "${DIR}" ]] || { echo "ERROR: ${DIR} is not a directory" >&2; exit 2; }
DIR="$(cd "${DIR}" && pwd)"

LINKS="$(mktemp)"
trap 'rm -f "${LINKS}"' EXIT
errors=0
fail() {
    echo "  $*" >&2
    errors=$((errors + 1))
}

# exists <site-path>: a built file, directory index or .html page for a path relative to the site root.
exists() {
    local p="${1#/}"
    [[ -z "${p}" || -f "${DIR}/${p}" || -f "${DIR}/${p%/}/index.html" || -f "${DIR}/${p}.html" ]]
}

# Every decision record in docs/adr/ must be built and listed in the site's Design decisions sidebar.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADRS=()
for adr in "${ROOT}"/docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
    name="$(basename "${adr}" .md)"
    ADRS+=("adr/${name}")
    grep -qF "'/adr/${name}'" "${ROOT}/docs/site/vocs.config.ts" \
        || fail "ADR ${name} missing from the Design decisions sidebar in docs/site/vocs.config.ts"
done
for page in "" guides/compose-your-own-diamond guides/selector-compatibility guides/storage-action \
    guides/hedera grants adr "${ADRS[@]}" src/contract.Lattice src/governance/contract.Governor \
    src/access/libraries/library.AccessControlLib; do
    exists "${page}" && [[ -n "${page}" || -f "${DIR}/index.html" ]] || fail "missing page /${page}"
done

# One "<target path>\t<page>\t<link>" row per local link, with the target relative to the site root.
grep -roE --include='*.html' '(href|src)="[^"]*"' "${DIR}" \
    | awk -v dir="${DIR}" -v base="${BASE}" '
        {
            i = index($0, ":"); file = substr($0, 1, i - 1); attr = substr($0, i + 1)
            link = attr; sub(/^[a-z]+="/, "", link); sub(/"$/, "", link)
            page = substr(file, length(dir) + 2)
            if (link == "" || link ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ || link ~ /^\/\// || link ~ /^#/) next
            target = link; sub(/[?#].*$/, "", target)
            if (link ~ /^\//) {
                if (target == base || index(target, base "/") == 1) { print substr(target, length(base) + 1) "\t" page "\t" link }
                else if (link ~ /#vocs-content$/) next
                else print "!BASE\t" page "\t" link
                next
            }
            # Relative link: resolve against the page directory.
            n = split(page, parts, "/"); out = ""
            for (k = 1; k < n; k++) out = out "/" parts[k]
            m = split(target, segs, "/")
            for (k = 1; k <= m; k++) {
                if (segs[k] == "" || segs[k] == ".") continue
                if (segs[k] == "..") sub(/\/[^\/]*$/, "", out); else out = out "/" segs[k]
            }
            print out "\t" page "\t" link
        }' >"${LINKS}"

while IFS=$'\t' read -r page link; do
    fail "${page}: root-absolute link outside ${BASE}: ${link}"
done < <(awk -F'\t' '$1 == "!BASE" { print $2 "\t" $3 }' "${LINKS}" | sort -u)

checked=0
while IFS=$'\t' read -r target page link; do
    checked=$((checked + 1))
    exists "${target}" || fail "${page}: broken local link ${link}"
done < <(awk -F'\t' '$1 != "!BASE"' "${LINKS}" | sort -t$'\t' -u -k1,1)

pages="$(find "${DIR}" -name '*.html' | wc -l | tr -d ' ')"
if [[ "${errors}" -gt 0 ]]; then
    echo "FAIL: ${errors} problem(s) in ${DIR} (listed above)." >&2
    exit 1
fi
echo "OK: ${pages} pages, ${checked} distinct local link targets, all under ${BASE} and present."
