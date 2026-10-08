#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-licenses.sh
#
# Dependency-free CI guard for license notices (#230). Fails when:
#   1. a `.sol` file under src/, script/ or test/ does not start with an
#      `SPDX-License-Identifier:` line;
#   2. any license id in that SPDX expression (split on OR / AND / WITH and
#      parentheses) has no license text in the repo (MIT -> LICENSE, anything
#      else -> LICENSES/<id>.txt);
#   3. a file under src/interfaces/external/ uses the `@author Modified from` form, or
#      (outside ercs/ and seal/, which keep older wording until #247) lacks the
#      `@author Vendored ...` / `@author ABI-equivalent interface authored fresh ...`
#      line or the `Upstream license:` note (AGENTS.md "External-source attribution");
#   4. a file under src/interfaces/external/ is missing from the third-party interface
#      table in lib/VENDORED.md, or that table lists a file that no longer exists.
#
# Usage: ./script/check-licenses.sh [root]   (`make license-check`; root defaults to the
#        repo root and exists so script/test-check-licenses.sh can run it on fixtures)
# ---------------------------------------------------------------------------
set -euo pipefail

cd "${1:-$(dirname "$0")/..}"

EXTERNAL=src/interfaces/external
VENDORED=lib/VENDORED.md
fail=0
nfiles=0

err() {
    echo "license-check: $*" >&2
    fail=1
}

ids=$(mktemp)
trap 'rm -f "$ids"' EXIT

# 1. Every Solidity file starts with an SPDX line; record each license id in its expression.
while IFS= read -r f; do
    line=$(head -n 1 "$f")
    case "$line" in
        *SPDX-License-Identifier:*) ;;
        *)
            err "$f does not start with an SPDX-License-Identifier line"
            continue
            ;;
    esac
    expr=$(printf '%s\n' "$line" | sed -E 's/.*SPDX-License-Identifier:[[:space:]]*//; s/[[:space:]]*\*\/[[:space:]]*$//; s/[[:space:]]+$//')
    toks=$(printf '%s\n' "$expr" | tr '()' '  ' | tr -s ' \t' '\n' | grep -vE '^(OR|AND|WITH)?$' || true)
    if [ -z "$toks" ]; then
        err "$f has an empty SPDX-License-Identifier expression"
        continue
    fi
    printf '%s\n' "$toks" >>"$ids"
    nfiles=$((nfiles + 1))
done < <(find src script test -name '*.sol' -type f | sort)

# 2. Every SPDX id in use has its license text in the repo.
for id in $(sort -u "$ids"); do
    case "$id" in
        MIT) grep -q '^MIT License' LICENSE || err "SPDX id MIT is used but LICENSE is not the MIT text" ;;
        *) [ -f "LICENSES/$id.txt" ] || err "SPDX id $id is used but LICENSES/$id.txt is missing" ;;
    esac
done

# 3. External interfaces use the vendored (or fresh ABI-equivalent) attribution form.
while IFS= read -r f; do
    if grep -qiE '@author +Modified from' "$f"; then
        err "$f uses '@author Modified from'; use '@author Vendored minimal subset of ...' (AGENTS.md)"
        continue
    fi
    case "$f" in "$EXTERNAL"/ercs/* | "$EXTERNAL"/seal/*) continue ;; esac
    grep -qE '@author +(Vendored|ABI-equivalent interface authored fresh)' "$f" \
        || err "$f has no '@author Vendored ...' (or '@author ABI-equivalent interface authored fresh ...') line (AGENTS.md)"
    grep -qE 'Upstream license: *[^ ]' "$f" || err "$f has no 'Upstream license: <id>.' note (AGENTS.md)"
done < <(find "$EXTERNAL" -name '*.sol' -type f | sort)

# 4. Every external interface is listed in the lib/VENDORED.md table.
while IFS= read -r f; do
    rel=${f#"$EXTERNAL"/}
    grep -qF "| \`$rel\` |" "$VENDORED" || err "$f is missing from the third-party interface table in $VENDORED"
done < <(find "$EXTERNAL" -name '*.sol' -type f | sort)

# 5. ...and the table lists no file that no longer exists.
while IFS= read -r rel; do
    [ -f "$EXTERNAL/$rel" ] || err "$VENDORED lists \`$rel\` but $EXTERNAL/$rel does not exist"
done < <(sed -n '/^## Third-party interfaces/,/^## /p' "$VENDORED" | grep -oE '^\| `[^`]+\.sol` \|' | sed -E 's/^\| `([^`]+)` \|$/\1/')

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "license-check: OK ($nfiles Solidity files; ids: $(sort -u "$ids" | tr '\n' ' '))"
