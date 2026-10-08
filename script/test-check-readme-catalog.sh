#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-check-readme-catalog.sh
#
# Regression tests for script/check-readme-catalog.sh. Each case builds a minimal fixture
# tree in a temp dir, runs the checker on it, and asserts pass/fail.
#
# Usage: ./script/test-check-readme-catalog.sh   (`make readme-check` runs it)
# ---------------------------------------------------------------------------
set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-readme-catalog.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
n=0

# fixture <dir>: a tree that passes; cases then break one thing.
fixture() {
    local d=$1
    mkdir -p "$d/src/access/libraries" "$d/src/interfaces/access" "$d/src/examples" "$d/src/utils/libraries/math" \
        "$d/lib/diamond-lib/src/facets"
    touch "$d/src/Lattice.sol" "$d/src/access/AccessControl.sol" "$d/src/access/Ownable.sol" \
        "$d/src/access/AccessControlInit.sol" "$d/src/access/libraries/AccessControlLib.sol" \
        "$d/src/interfaces/access/IAccessControl.sol" "$d/src/examples/Demo.sol" \
        "$d/src/utils/libraries/math/Math.sol" "$d/lib/diamond-lib/src/facets/OwnableFacet.sol"
    cat >"$d/README.md" <<'EOF'
# Lattice

Lattice is a library. `Lattice` here is outside the catalog.

## Modules

| Area | Modules |
|------|---------|
| Core | `Lattice` (create and `initialize` it in one transaction) |
| `access/` | `AccessControl`, `Ownable` (re-exports diamond-lib's `OwnableFacet`) |

**Utility libraries:** `math/Math`, `SignerType.HederaAccount`, `rebalance()`.

## Other

`NotAContract` is outside the catalog.
EOF
}

# expect <pass|fail> <name> <setup-snippet>
expect() {
    local want=$1 name=$2 setup=$3 d got
    n=$((n + 1))
    d="$tmp/case$n"
    fixture "$d"
    (cd "$d" && eval "$setup")
    if "$CHECK" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (expected $want, got $got)"
        failures=$((failures + 1))
    fi
}

# readme <sed-expression>: edit the fixture README in place (portable to BSD and GNU sed).
readme() { sed -e "$1" README.md >README.tmp && mv README.tmp README.md; }

expect pass "baseline fixture" ':'
expect fail "contract missing from catalog" 'touch src/access/AccessManager.sol'
expect fail "root contract missing from catalog" 'touch src/Receive.sol'
expect fail "contract named only outside the catalog" 'readme "s/\`Lattice\` (create/Lattice (create/"'
expect fail "contract named only after the catalog" 'touch src/NotAContract.sol'
expect fail "prefix of a listed name does not count" 'touch src/access/Access.sol'
expect fail "unbackticked name does not count" 'touch src/access/AccessManaged.sol
readme "s/\`Ownable\`/\`Ownable\`, AccessManaged/"'
expect pass "Init file need not be listed" 'touch src/access/AccessManagerInit.sol'
expect pass "Lib file beside its facet need not be listed" 'touch src/access/AccessManagerLib.sol'
expect pass "libraries/ file need not be listed" 'touch src/access/libraries/AccessManagerLib.sol src/utils/libraries/Strings.sol'
expect pass "interface need not be listed" 'touch src/interfaces/access/IAccessManager.sol'
expect pass "example need not be listed" 'touch src/examples/OtherDemo.sol'
expect fail "catalog names a missing contract" 'readme "s/\`Ownable\` (/\`Ownable\`, \`AccessManager\` (/"'
expect fail "catalog names a removed contract" 'rm src/access/AccessControl.sol'
expect fail "catalog names a missing all-caps contract" 'readme "s/\`math\/Math\`/\`math\/Math\`, \`ECDSA\`/"'
expect pass "catalog may name an Init, Lib or example" 'readme "s/\`math\/Math\`/\`math\/Math\`, \`AccessControlInit\`, \`AccessControlLib\`, \`Demo\`/"'
expect fail "path token resolves only at its path" 'mv src/utils/libraries/math/Math.sol src/utils/libraries/Math.sol'
expect fail "name from diamond-lib missing" 'rm lib/diamond-lib/src/facets/OwnableFacet.sol'
expect fail "no Modules section" 'readme "s/^## Modules$/## Packages/"'

echo "$((n - failures))/$n readme-check cases passed"
[ "$failures" -eq 0 ]
