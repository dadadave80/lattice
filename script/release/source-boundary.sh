#!/usr/bin/env bash
# A published source freeze must survive squash-merging/deleting the current feature branch.
set -euo pipefail
[[ "${1:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'release source: expected a full source commit' >&2; exit 1; }
source_commit=$1
cd "${2:-$(dirname "$0")/../..}"
git cat-file -e "$source_commit^{commit}"
for retained in origin/dev origin/main; do
    if git rev-parse --verify "$retained^{commit}" >/dev/null 2>&1 && git merge-base --is-ancestor "$source_commit" "$retained"; then
        exit 0
    fi
done
echo 'release source: freeze an already-merged commit retained by origin/dev or origin/main; use fixture mode for feature builds' >&2
exit 1
