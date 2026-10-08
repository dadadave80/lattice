#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# closing-issues.sh
#
# Prints the issue numbers a pull-request body closes, one per line, in first-seen
# order and without duplicates. GitHub only acts on closing keywords when a PR merges
# into the default branch (main), so .github/workflows/close-linked-issues.yml runs
# this on PRs merged into dev and closes the issues itself.
#
# Matches GitHub's keywords (close/closes/closed, fix/fixes/fixed, resolve/resolves/
# resolved; any case, optional colon) followed by `#N`, `<repo>#N` or
# `https://github.com/<repo>/issues/N`. References to other repositories and
# non-closing wording ("Part of #N", "see #N") are ignored.
#
# Usage: ./script/closing-issues.sh <owner/repo> < body.md
#        (script/test-closing-issues.sh covers the matching rules)
# ---------------------------------------------------------------------------
set -euo pipefail

repo=${1:?usage: closing-issues.sh <owner/repo> < body}
# Escape ERE metacharacters ('.', '-' and '_' are legal in owner/repo names).
re_repo=$(printf '%s' "$repo" | sed 's/[][\.*^$+?(){}|]/\\&/g')

keyword='(close[sd]?|fix(e[sd])?|resolve[sd]?)'
ref="(#|${re_repo}#|https://github\\.com/${re_repo}/issues/)[0-9]+"

{ grep -oiE "(^|[^[:alnum:]_])${keyword}:?[[:space:]]+${ref}" || true; } \
    | grep -oE '[0-9]+$' \
    | awk '!seen[$0]++' \
    || true
