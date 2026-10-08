#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-check-licenses.sh
#
# Regression tests for script/check-licenses.sh. Each case builds a minimal fixture
# tree in a temp dir, runs the checker on it, and asserts pass/fail.
#
# Usage: ./script/test-check-licenses.sh   (`make license-check` runs it)
# ---------------------------------------------------------------------------
set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-licenses.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
n=0

GOOD_HEADER='/// @author Vendored minimal subset of Foo (https://example.com).
///         Upstream license: MIT.'

# fixture <dir>: a tree that passes; cases then break one thing.
fixture() {
    local d=$1
    mkdir -p "$d/src/interfaces/external/foo" "$d/script" "$d/test" "$d/lib" "$d/LICENSES"
    printf 'MIT License\n' >"$d/LICENSE"
    printf 'Apache License\n' >"$d/LICENSES/Apache-2.0.txt"
    printf '// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\n%s\ninterface IFoo {}\n' \
        "$GOOD_HEADER" >"$d/src/interfaces/external/foo/IFoo.sol"
    printf '// SPDX-License-Identifier: Apache-2.0\npragma solidity ^0.8.30;\n' >"$d/test/T.sol"
    printf '## Third-party interfaces\n\n| File | Upstream | Upstream license | Form |\n|---|---|---|---|\n| `foo/IFoo.sol` | foo | MIT | subset |\n\n## Other\n' \
        >"$d/lib/VENDORED.md"
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

sol() { printf '%s\npragma solidity ^0.8.30;\n' "$1" >"$2"; }
ext() { printf '// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\n%s\ninterface IFoo {}\n' "$1" >src/interfaces/external/foo/IFoo.sol; }

expect pass "baseline fixture" ':'
expect fail "missing SPDX line" 'sol "pragma solidity ^0.8.30;" test/T.sol'
expect fail "SPDX not on line 1" 'printf "pragma solidity ^0.8.30;\n// SPDX-License-Identifier: MIT\n" >test/T.sol'
expect fail "SPDX id with no license text" 'sol "// SPDX-License-Identifier: GPL-3.0-only" test/T.sol'
expect fail "compound OR with unknown second id" 'sol "// SPDX-License-Identifier: MIT OR GPL-3.0-only" test/T.sol'
expect fail "WITH exception id without text" 'sol "// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception" test/T.sol'
expect pass "parenthesised OR of known ids" 'sol "// SPDX-License-Identifier: (Apache-2.0 OR MIT)" test/T.sol'
expect pass "block-comment SPDX" 'sol "/* SPDX-License-Identifier: MIT */" test/T.sol'
expect fail "external: @author Modified from" 'ext "/// @author Modified from Foo (https://example.com)
///         Upstream license: MIT."'
expect fail "external: lowercase @author modified from" 'ext "/// @author modified from Foo (https://example.com)
///         Upstream license: MIT."'
expect fail "external: other @author wording" 'ext "/// @author Copied from Foo (https://example.com)
///         Upstream license: MIT."'
expect fail "external: no Upstream license note" 'ext "/// @author Vendored minimal subset of Foo (https://example.com)."'
expect pass "external: fresh ABI-equivalent form" 'ext "/// @author ABI-equivalent interface authored fresh from Foo'"'"'s public ABI (https://example.com).
///         Upstream license: BUSL-1.1 (not copied)."'
expect pass "external: ercs/ keeps older wording" 'mkdir -p src/interfaces/external/ercs
printf "// SPDX-License-Identifier: MIT\n/// @author Vendored from OZ\ninterface IE {}\n" >src/interfaces/external/ercs/IE.sol
printf "| \`ercs/IE.sol\` | oz | MIT | subset |\n" >>lib/VENDORED.md'
expect fail "external: file missing from table" 'cp src/interfaces/external/foo/IFoo.sol src/interfaces/external/foo/IBar.sol'
expect fail "table lists a missing file" 'rm src/interfaces/external/foo/IFoo.sol'

echo "$((n - failures))/$n license-check cases passed"
[ "$failures" -eq 0 ]
