#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-readme-catalog.sh
#
# Dependency-free CI guard for the README module catalog (#242). The catalog is
# every backticked token in README.md's `## Modules` section, from that heading
# to the next `## ` heading. Text elsewhere in the README does not count, so the
# project name "Lattice" in the introduction cannot stand in for `Lattice`.
#
# Fails when:
#   1. a contract file in src/ has no exact backticked entry (`Name`) in the
#      catalog. A contract file is any src/**/*.sol except
#        - src/interfaces/**   (ABIs, errors and events),
#        - src/examples/**     (demo contracts, not library modules),
#        - any path with a libraries/ directory (the library layer),
#        - *Init.sol           (one-shot initializers),
#        - *Lib.sol            (library-layer files kept beside their facet).
#      Name is the file name without .sol, not the declared contract, because
#      src/access/Ownable.sol re-exports diamond-lib's OwnableFacet and declares
#      nothing. Test helpers live under test/, never src/, so none are in scope;
#   2. the catalog names a contract that does not exist. Every token that is an
#      identifier starting with an upper-case letter (`ERC20Votes`, `ECDSA`),
#      optionally behind lower-case directories (`math/Math`), must match a
#      src/**/<token>.sol file. All of src/ counts here, so the catalog may also
#      name an initializer, library or example. A name not found in src/ may
#      come from lib/diamond-lib/src/ (the Ownable row cites `OwnableFacet`).
#      Tokens with other characters (`initialize`, `rebalance()`, `access/`,
#      `SignerType.HederaAccount`) are prose and are not checked;
#   3. README.md has no `## Modules` section.
#
# Usage: ./script/check-readme-catalog.sh [root]   (`make readme-check`; root defaults
#        to the repo root and exists so script/test-check-readme-catalog.sh can run it
#        on fixtures)
# ---------------------------------------------------------------------------
set -euo pipefail

cd "${1:-$(dirname "$0")/..}"

README=README.md
DEPS=lib/diamond-lib/src
fail=0

err() {
    echo "readme-check: $*" >&2
    fail=1
}

catalog=$(mktemp)
sources=$(mktemp)
trap 'rm -f "$catalog" "$sources"' EXIT

if ! grep -qE '^## Modules[[:space:]]*$' "$README"; then
    err "$README has no '## Modules' section"
    exit 1
fi
# The catalog: one backticked token per line, backticks stripped.
awk '/^## Modules[[:space:]]*$/ { f = 1; next } f && /^## / { exit } f' "$README" \
    | { grep -oE '`[^`]+`' || true; } | tr -d '`' | sort -u >"$catalog"

find src -name '*.sol' -type f | sort >"$sources"
[ -d "$DEPS" ] && find "$DEPS" -name '*.sol' -type f | sort >>"$sources"

# 1. Every contract file has an exact backticked entry in the catalog.
ncontracts=0
while IFS= read -r f; do
    name=$(basename "$f" .sol)
    ncontracts=$((ncontracts + 1))
    grep -qxF "$name" "$catalog" || err "$f is missing from the $README '## Modules' catalog (add \`$name\`)"
done < <(find src -name '*.sol' -type f \
    -not -path 'src/interfaces/*' -not -path 'src/examples/*' -not -path '*/libraries/*' \
    -not -name '*Init.sol' -not -name '*Lib.sol' | sort)

# 2. Every contract-like token in the catalog names an existing .sol file.
nnames=0
while IFS= read -r token; do
    nnames=$((nnames + 1))
    grep -q "/${token}[.]sol\$" "$sources" \
        || err "$README '## Modules' names \`$token\` but no src/**/$token.sol (or $DEPS/**/$token.sol) exists"
done < <(grep -E '^([a-z0-9_]+/)*[A-Z][A-Za-z0-9]*$' "$catalog" || true)

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "readme-check: OK ($ncontracts contract files listed; $nnames catalog names resolve)"
