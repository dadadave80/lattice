#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-closing-issues.sh
#
# Regression tests for script/closing-issues.sh. Each case feeds a PR body to the
# parser and compares the issue numbers it prints (space-joined) with the expected list.
#
# Usage: ./script/test-closing-issues.sh   (`make scripts-check` runs it)
# ---------------------------------------------------------------------------
set -euo pipefail

PARSE="$(cd "$(dirname "$0")" && pwd)/closing-issues.sh"
REPO=dadadave80/lattice
failures=0
n=0

# expect <name> <expected numbers, space-separated> <body>
expect() {
    local name=$1 want=$2 body=$3 got
    n=$((n + 1))
    got=$(printf '%b' "$body" | "$PARSE" "$REPO" | tr '\n' ' ' | sed 's/ $//')
    if [ "$got" = "$want" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (expected '$want', got '$got')"
        failures=$((failures + 1))
    fi
}

expect "close" "1" "close #1"
expect "closes, trailing punctuation" "239" "Closes #239 (D30)."
expect "closed" "3" "closed #3"
expect "fix / fixes / fixed" "4 5 6" "fix #4, fixes #5 and fixed #6"
expect "resolve / resolves / resolved" "7 8 9" "Resolve #7\nRESOLVES #8\nresolved #9"
expect "colon after keyword" "10" "Closes: #10"
expect "several refs across lines" "233 225" "Closes #233.\nCloses #225."
expect "duplicates printed once" "220" "Closes #220\n\nFixes #220"
expect "CRLF line endings" "11 12" "Closes #11\r\nCloses #12\r\n"
expect "same-repo long form" "13" "Fixes dadadave80/lattice#13"
expect "same-repo issue URL" "14" "Closes https://github.com/dadadave80/lattice/issues/14"
expect "keyword inside a word" "" "prefixes #15, unfixed #16, foreclosed #17"
expect "non-closing wording" "" "Part of #238\nRelated to #18\nsee #19\nRefs #20"
expect "other repository" "" "Closes foo/bar#21\nFixes dadadave80/lattice-fork#22"
expect "other repository URL" "" "Closes https://github.com/foo/bar/issues/23"
expect "keyword with no reference" "" "Closes the gap in #24"
expect "empty body" "" ""

echo "$((n - failures))/$n closing-issues cases passed"
[ "$failures" -eq 0 ]
